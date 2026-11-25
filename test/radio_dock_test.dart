import 'dart:async';
import 'dart:typed_data';

import 'package:amid_offgrid/models/mesh_wire.dart';
import 'package:amid_offgrid/services/radio_dock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'radio_support.dart';
import 'support.dart';

void main() {
  test(
    'a cancelled scan finishing late cannot overwrite a new ready connection',
    () async {
      final f = await openTestStore(),
          transport = FixtureRadio()..pendingScan = Completer<void>();
      final radio = RadioDockService(f.store, transport);
      try {
        final pending = expectLater(radio.scan(), throwsStateError);
        await Future<void>.delayed(Duration.zero);
        expect(radio.busy, isTrue);
        await radio.stop();
        await radio.connect('one');
        transport.pendingScan!.complete();
        await pending;
        expect(radio.ready, isTrue);
        expect(radio.busy, isFalse);
        expect(radio.status, contains('Модуль готовий'));
      } finally {
        radio.dispose();
        await f.store.close();
        await f.root.delete(recursive: true);
      }
    },
  );
  test(
    'configuration must confirm its nonce; cancel discards late replies',
    () async {
      final f = await openTestStore(),
          transport = FixtureRadio()..autoConfigure = false;
      final radio = RadioDockService(f.store, transport);
      try {
        final pending = expectLater(radio.connect('one'), throwsStateError);
        await Future<void>.delayed(Duration.zero);
        transport.emit(meshUint(7, 999));
        await radio.flushIncoming();
        expect(radio.ready, isFalse);
        await radio.stop();
        await pending;
        transport.text('Late');
        await radio.flushIncoming();
        expect(f.store.messages, isEmpty);
        expect(radio.ready, isFalse);
      } finally {
        radio.dispose();
        await f.store.close();
        await f.root.delete(recursive: true);
      }
    },
  );
  test('BLE write, radio queue and strict recipient ACK are distinct persistent states', () async {
    final f = await openTestStore(), transport = FixtureRadio();
    final radio = RadioDockService(f.store, transport);
    try {
      await radio.connect('one');
      radio.chooseChannel(1);
      expect(radio.canSend, isTrue);
      await radio.sendText('Повідомлення', to: 0x1234abcd);
      final id = transport.lastId;
      expect(radio.transmissions.single.state, RadioDelivery.bluetooth);
      expect(f.store.messages.single.status, 'draft');
      transport.queued(id);
      await radio.flushIncoming();
      expect(radio.transmissions.single.state, RadioDelivery.queued);
      expect(f.store.messages.single.status, 'transferred');
      transport.ack(id, from: 0x22334455);
      await radio.flushIncoming();
      transport.ack(id, to: meshBroadcast);
      await radio.flushIncoming();
      transport.ack(id, channel: 0);
      await radio.flushIncoming();
      expect(f.store.messages.single.status, 'transferred');
      transport.ack(id);
      await radio.flushIncoming();
      expect(radio.transmissions.single.state, RadioDelivery.acknowledged);
      expect(f.store.messages.single.status, 'delivered');
      transport.queued(id);
      await radio.flushIncoming();
      expect(f.store.messages.single.status, 'delivered');
      await expectLater(
        radio.sendText('Too fast', to: 0x1234abcd),
        throwsStateError,
      );
    } finally {
      radio.dispose();
      await f.store.close();
      await f.root.delete(recursive: true);
    }
  });
  test('broadcast never becomes delivered from an implicit ACK, and times out without success', () async {
    final f = await openTestStore(), transport = FixtureRadio();
    final radio = RadioDockService(
      f.store,
      transport,
      ackTimeout: const Duration(milliseconds: 30),
    );
    try {
      await radio.connect('one');
      radio.chooseChannel(1);
      await radio.sendText('Усім', to: meshBroadcast);
      final id = transport.lastId;
      transport.queued(id);
      transport.ack(id);
      await radio.flushIncoming();
      expect(f.store.messages.single.status, 'transferred');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(radio.transmissions.single.state, RadioDelivery.unconfirmed);
    } finally {
      radio.dispose();
      await f.store.close();
      await f.root.delete(recursive: true);
    }
  });
  test('duplicate incoming text persists once; invalid radio packets and TX failures are not success', () async {
    final f = await openTestStore(), transport = FixtureRadio();
    final radio = RadioDockService(f.store, transport);
    try {
      await radio.connect('one');
      radio.chooseChannel(1);
      transport.text('Ліс');
      transport.text('Ліс');
      transport.emit(Uint8List.fromList([18, 250]));
      await radio.flushIncoming();
      expect(f.store.messages.single.body, 'Ліс');
      transport.writeFails = true;
      await expectLater(
        radio.sendText('Failure', to: 0x1234abcd),
        throwsStateError,
      );
      expect(radio.transmissions.single.state, RadioDelivery.failed);
      expect(
        f.store.messages.where((m) => m.direction == 'out').single.status,
        'draft',
      );
      await radio.stop();
      transport.text('After stop', id: 901);
      await radio.flushIncoming();
      expect(f.store.messages.where((m) => m.direction == 'in'), hasLength(1));
    } finally {
      radio.dispose();
      await f.store.close();
      await f.root.delete(recursive: true);
    }
  });
  test('unsafe radio configurations refuse send; disconnect cancels an in-flight write', () async {
    final f = await openTestStore(), transport = FixtureRadio();
    final radio = RadioDockService(f.store, transport);
    try {
      await radio.connect('one');
      radio.chooseChannel(1);
      radio.channels[1] = const MeshChannel(1, 'Public', false, false);
      await expectLater(radio.sendText('no', to: 0x1234abcd), throwsStateError);
      radio.channels[1] = const MeshChannel(1, 'Private', true, true);
      await expectLater(radio.sendText('no', to: 0x1234abcd), throwsStateError);
      radio.channels[1] = const MeshChannel(1, 'Private', true, false);
      radio.region = 1;
      await expectLater(radio.sendText('no', to: 0x1234abcd), throwsStateError);
      radio.region = 3;
      transport.pendingWrite = Completer<void>();
      final pending = expectLater(
        radio.sendText('Cancel', to: 0x1234abcd),
        throwsStateError,
      );
      await f.store.flush();
      await Future<void>.delayed(Duration.zero);
      await radio.stop();
      transport.pendingWrite!.complete();
      await pending;
      expect(
        radio.transmissions.single.state,
        isNot(RadioDelivery.acknowledged),
      );
      expect(f.store.messages.single.status, 'draft');
    } finally {
      radio.dispose();
      await f.store.close();
      await f.root.delete(recursive: true);
    }
  });
}
