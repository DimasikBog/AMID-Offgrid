import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:amid_offgrid/services/secure_channel.dart';
import 'package:amid_offgrid/services/frame_codec.dart';
import 'package:amid_offgrid/models/data.dart';

void main() {
  group('paired authenticated transport', () {
    test('both directions, tampering, reflection and replay', () async {
      final ticket = PairingTicket.create(),
          host = await SecureChannel.create(ticket, host: true),
          guest = await SecureChannel.create(
            PairingTicket.parse(ticket.encode()),
            host: false,
          );
      final wire = await host.seal({'type': 'hello', 'text': 'Привіт!'});
      final damaged = Uint8List.fromList(wire);
      damaged[damaged.length - 1] ^= 1;
      await expectLater(guest.open(damaged), throwsA(anything));
      await expectLater(host.open(wire), throwsA(anything));
      expect((await guest.open(wire))['text'], 'Привіт!');
      await expectLater(guest.open(wire), throwsFormatException);
      expect(
        (await host.open(await guest.seal({'type': 'ack'})))['type'],
        'ack',
      );
    });
    test('wrong secret and wrong session cannot decrypt', () async {
      final ticket = PairingTicket.create(),
          host = await SecureChannel.create(ticket, host: true),
          wrong = await SecureChannel.create(
            PairingTicket.create(),
            host: false,
          );
      final wire = await host.seal({'body': 'private'});
      await expectLater(wrong.open(wire), throwsA(anything));
    });
    test(
      'reordered packets accepted once within bounded replay window',
      () async {
        final t = PairingTicket.create(),
            a = await SecureChannel.create(t, host: true),
            b = await SecureChannel.create(t, host: false);
        final packets = <Uint8List>[];
        for (var i = 0; i < 260; i++) {
          packets.add(await a.seal({'i': i}));
        }
        expect((await b.open(packets[259]))['i'], 259);
        expect((await b.open(packets[258]))['i'], 258);
        await expectLater(b.open(packets[0]), throwsFormatException);
        await expectLater(b.open(packets[259]), throwsFormatException);
      },
    );
    test('QR and payload bounds', () async {
      expect(() => PairingTicket.parse('x' * 501), throwsFormatException);
      expect(
        () => PairingTicket.parse(
          '{"format":"AMID_PAIR","version":1,"id":"a","secret":"b"}',
        ),
        throwsFormatException,
      );
      final a = await SecureChannel.create(PairingTicket.create(), host: true);
      await expectLater(a.seal({'body': 'x' * 24001}), throwsFormatException);
    });
  });
  group('BLE fragmentation', () {
    test('4000 Cyrillic characters at default MTU20 end to end', () async {
      final t = PairingTicket.create(),
          a = await SecureChannel.create(t, host: true),
          b = await SecureChannel.create(t, host: false);
      final message = Message(
        'test-id',
        'ї' * 4000,
        '2026-11-22T10:00:00Z',
        'out',
        'draft',
      );
      final packet = await a.seal({
            'type': 'message',
            'message': message.toWire(),
          }),
          frames = fragmentPacket(packet, mtu: 20, id: 65535),
          assembler = FrameAssembler();
      expect(frames.every((f) => f.length <= 20), isTrue);
      Uint8List? assembled;
      for (final frame in frames.reversed) {
        assembled = assembler.accept(frame) ?? assembled;
      }
      final decoded = await b.open(assembled!);
      expect(
        Message.parse(Json.from(decoded['message'] as Map)).body,
        message.body,
      );
    });
    test('duplicate fragments, conflicting duplicates, limits and timeout', () {
      final packet = Uint8List.fromList(List.generate(100, (i) => i)),
          frames = fragmentPacket(packet, mtu: 20, id: 1),
          a = FrameAssembler();
      expect(a.accept(frames.first), isNull);
      expect(a.accept(frames.first), isNull);
      final bad = Uint8List.fromList(frames.first);
      bad[8] ^= 1;
      expect(() => a.accept(bad), throwsFormatException);
      expect(
        () => fragmentPacket(Uint8List(32769), mtu: 20, id: 0),
        throwsFormatException,
      );
      expect(
        () => fragmentPacket(packet, mtu: 19, id: 0),
        throwsFormatException,
      );
      final malformed = Uint8List.fromList(frames.first);
      ByteData.sublistView(malformed).setUint16(6, 4097);
      expect(() => a.accept(malformed), throwsFormatException);
      a.clear();
      final at = DateTime.utc(2026);
      a.accept(frames.first, now: at);
      final replacement = fragmentPacket(
        Uint8List.fromList([1, 2]),
        mtu: 20,
        id: 1,
      ).single;
      expect(a.accept(replacement, now: at.add(const Duration(seconds: 46))), [
        1,
        2,
      ]);
    });
    test('at most four partially assembled packets', () {
      final a = FrameAssembler();
      for (var i = 0; i < 4; i++) {
        a.accept(fragmentPacket(Uint8List(100), mtu: 20, id: i).first);
      }
      expect(
        () => a.accept(fragmentPacket(Uint8List(100), mtu: 20, id: 4).first),
        throwsFormatException,
      );
    });
  });
}
