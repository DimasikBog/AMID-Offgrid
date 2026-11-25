import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:amid_offgrid/models/mesh_wire.dart';
import 'package:amid_offgrid/services/radio_dock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'radio_support.dart';
import 'support.dart';

void main() {
  test('field report excludes MQTT ACK, duplicate texts and all payload identifiers', () async {
    final f = await openTestStore(), transport = FixtureRadio();
    final radio = RadioDockService(f.store, transport);
    try {
      await radio.connect('one');
      radio.chooseChannel(1);
      radio.startFieldTest();
      expect(
        transport.writes,
        hasLength(1),
      ); // Starting a test never transmits.
      await radio.sendText(
        'Private payload 50.12345, 15.12345',
        to: 0x1234abcd,
      );
      final id = transport.lastId;
      transport.queued(id);
      transport.ack(id, viaMqtt: true);
      transport.text('MQTT only', id: 5, viaMqtt: true);
      await radio.flushIncoming();
      expect(radio.transmissions.single.state, RadioDelivery.queued);
      expect(radio.fieldTest!.acknowledged, 0);
      expect(radio.fieldTest!.receivedTexts, 0);
      transport.ack(id);
      transport.ack(id);
      transport.text('Private incoming 51.23456, 16.23456');
      transport.text('Private incoming 51.23456, 16.23456');
      transport.emit(Uint8List.fromList([18, 250]));
      await radio.flushIncoming();
      await radio.finishFieldTest();
      expect(radio.fieldTest, isNull);
      expect(radio.fieldReportSaved, isTrue);
      final report = f.store.radioReports.single;
      expect(report.attempts, 1);
      expect(report.acknowledged, 1);
      expect(report.received, 1);
      expect(report.toJson()['processingErrors'], 1);
      expect((report.toJson()['rssiDbm'] as Map)['count'], 2);
      final encoded = jsonEncode(report.toJson());
      for (final private in [
        'Private',
        '50.12345',
        '51.23456',
        '!1234abcd',
        '1234abcd',
        'MQTT only',
      ]) {
        expect(encoded, isNot(contains(private)));
      }
      transport.text('After finish', id: 999);
      await radio.flushIncoming();
      expect(f.store.radioReports.single.received, 1);
    } finally {
      radio.dispose();
      await f.store.close();
      await f.root.delete(recursive: true);
    }
  });
  test('disconnect finalizes once, preserves pending as interrupted and a new test starts fresh', () async {
    final f = await openTestStore(), transport = FixtureRadio();
    final radio = RadioDockService(f.store, transport);
    try {
      await radio.connect('one');
      radio.chooseChannel(1);
      radio.startFieldTest();
      await radio.sendText('Pending', to: 0x1234abcd);
      await radio.stop();
      await radio.finishFieldTest();
      expect(f.store.radioReports, hasLength(1));
      final report = f.store.radioReports.single.toJson();
      expect(report['reason'], 'disconnected');
      expect((report['unicast'] as Map)['interrupted'], 1);
      expect((report['unicast'] as Map)['unconfirmed'], 0);
      await radio.stop();
      expect(f.store.radioReports, hasLength(1));
      await radio.connect('one');
      radio.chooseChannel(1);
      radio.startFieldTest();
      expect(radio.fieldTest!.attempts, 0);
      radio.channels[2] = const MeshChannel(2, 'Other', true, false);
      radio.chooseChannel(2);
      await radio.finishFieldTest();
      expect(
        f.store.radioReports.first.toJson()['reason'],
        'configurationChanged',
      );
    } finally {
      radio.dispose();
      await f.store.close();
      await f.root.delete(recursive: true);
    }
  });
  test(
    'failed report save stays visible and blocks replacing the unsaved report',
    () async {
      final f = await openTestStore(), transport = FixtureRadio();
      final radio = RadioDockService(f.store, transport);
      try {
        await radio.connect('one');
        radio.startFieldTest();
        await f.store.backend.db.execute(
          "CREATE TRIGGER field_report_fail BEFORE INSERT ON state BEGIN SELECT RAISE(ABORT, 'fixture save failure'); END",
        );
        await radio.finishFieldTest();
        expect(radio.fieldSaveError, isNotNull);
        expect(radio.fieldReportSaved, isFalse);
        expect(radio.lastFieldReport, isNotNull);
        expect(radio.startFieldTest, throwsStateError);
        await f.store.backend.db.execute('DROP TRIGGER field_report_fail');
        await radio.saveFieldReport();
        expect(radio.fieldSaveError, isNull);
        expect(radio.fieldReportSaved, isTrue);
        expect(f.store.radioReports, hasLength(1));
      } finally {
        radio.dispose();
        await f.store.close();
        await f.root.delete(recursive: true);
      }
    },
  );
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
