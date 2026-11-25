import 'dart:math';
import 'dart:typed_data';

import 'package:amid_offgrid/models/mesh_wire.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mesh_vectors.dart';

void main() {
  test(
    'wire bytes match independently generated official Python protobufs',
    () {
      expect(meshConfigRequest(12345), meshVector('config_request'));
      expect(
        meshTextRequest(
          text: 'Привіт, AMID',
          id: 0x10203040,
          to: 0x1234abcd,
          channel: 1,
        ),
        meshVector('text_request'),
      );
      expect(MeshEvent(meshVector('my_info')).myNode, 0x11223344);
      expect(MeshEvent(meshVector('metadata')).firmware, '2.7.26.54e0d8d');
      expect(MeshEvent(meshVector('lora')).lora, (
        region: 3,
        txEnabled: true,
        overrides: false,
      ));
      final channel = MeshEvent(meshVector('channel_test_key_only')).channel!;
      expect(channel.index, 1);
      expect(channel.hasFullKey, isTrue);
      expect(channel.uplink, isFalse);
      final node = MeshEvent(meshVector('node')).node!;
      expect(node.name, 'Вузол AMID');
      expect(node.latitude, closeTo(50, 1e-6));
      expect(node.longitude, closeTo(15, 1e-6));
      expect(node.battery, 73);
      expect(MeshEvent(meshVector('complete')).configId, 12345);
      expect(MeshEvent(meshVector('queued')).queue, (
        id: 0x10203040,
        result: 0,
      ));
      expect(MeshEvent(meshVector('incoming_text')).packet!.rssi, -97);
      expect(
        MeshEvent(meshVector('incoming_text')).packet!.snr,
        closeTo(7.25, .0001),
      );
      final ack = MeshEvent(meshVector('recipient_ack')).packet!;
      expect(ack.from, 0x1234abcd);
      expect(ack.to, 0x11223344);
      expect(ack.requestId, 0x10203040);
      expect(ack.routingError, 0);
      expect(
        MeshEvent(meshVector('incoming_text')).packet!.text,
        'Отримано з лісу',
      );
    },
  );
  test(
    'UTF-8 radio limit, destinations and hop bounds are enforced before BLE',
    () {
      expect(
        () => meshTextRequest(text: 'я' * 101, id: 1, to: 9, channel: 0),
        throwsFormatException,
      );
      expect(
        () => meshTextRequest(text: '😀' * 51, id: 1, to: 9, channel: 0),
        throwsFormatException,
      );
      expect(
        meshTextRequest(text: 'я' * 100, id: 1, to: 9, channel: 0).length,
        lessThan(512),
      );
      for (final value in [
        'abc',
        '!00000001',
        '!ffffffff',
        '!123456789',
        '!1234567x',
      ]) {
        expect(() => checkedMeshDestination(value), throwsFormatException);
      }
      expect(checkedMeshDestination('!AbCD1234'), 0xabcd1234);
      expect(
        () => meshTextRequest(text: 'x', id: 1, to: 9, channel: 0, hops: 7),
        throwsFormatException,
      );
    },
  );
  test('malformed and oversized protobufs fail with bounded format errors', () {
    for (final bytes in [
      <int>[0],
      [18, 127],
      [18, 255, 255, 255, 255, 15],
      [11],
      [8, ...List.filled(10, 255)],
      List.filled(513, 0),
    ]) {
      expect(() => MeshEvent(Uint8List.fromList(bytes)), throwsFormatException);
    }
    final random = Random(318);
    for (var i = 0; i < 2000; i++) {
      final bytes = Uint8List.fromList(
        List.generate(random.nextInt(513), (_) => random.nextInt(256)),
      );
      try {
        final e = MeshEvent(bytes);
        e.myNode;
        e.configId;
        e.firmware;
        e.channel;
        e.lora;
        e.node;
        e.packet?.text;
        e.packet?.routingError;
      } on FormatException {
        /* Bounded rejection is the expected parser result. */
      }
    }
  });
  test(
    'last known oneof wins and unknown scalar fields do not corrupt a packet',
    () {
      final bytes = [
        ...meshVector('my_info'),
        ...meshVector('complete'),
        ...(MeshWriter()..uint(100, 12)).take(),
      ];
      final e = MeshEvent(Uint8List.fromList(bytes));
      expect(e.myNode, isNull);
      expect(e.configId, 12345);
    },
  );
}
