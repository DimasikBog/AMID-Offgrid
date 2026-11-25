import 'dart:convert';

import 'package:amid_offgrid/services/backend_native.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'radio_field_support.dart';
import 'support.dart';

void main() {
  test('reports survive restart and backup; legacy backups and failed merges preserve state', () async {
    final f = await openTestStore();
    AppStore store = f.store;
    try {
      final report = session().finish('manual');
      await store.saveRadioReport(report);
      final backup = store.backup();
      await store.close();
      store = await AppStore.open(
        backend: await PlatformBackend.open(
          factory: databaseFactoryFfi,
          root: f.root,
        ),
      );
      expect(store.radioReports.single.toJson(), report.toJson());
      await store.deleteRadioReport(report.id);
      await store.restore(backup);
      final legacy = store.backup()..remove('radioReports');
      await store.restore(legacy);
      expect(store.radioReports.single.id, report.id);
      final before = jsonEncode(store.snapshot());
      final conflicting = store.backup();
      ((conflicting['radioReports'] as List).single as Map)['reason'] =
          'disconnected';
      await expectLater(store.restore(conflicting), throwsFormatException);
      expect(jsonEncode(store.snapshot()), before);
      final invalid = store.backup();
      ((invalid['radioReports'] as List).single as Map)['nodeId'] = 'private';
      await expectLater(store.restore(invalid), throwsFormatException);
      expect(jsonEncode(store.snapshot()), before);
    } finally {
      await store.close();
      await f.root.delete(recursive: true);
    }
  });

  test('history keeps at most twenty reports without duplicating repeated saves', () async {
    final f = await openTestStore();
    try {
      for (var i = 0; i < 23; i++) {
        final report = session(
          id: '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
        ).finish('manual');
        await f.store.saveRadioReport(report);
        await f.store.saveRadioReport(report);
      }
      expect(f.store.radioReports, hasLength(20));
      expect(f.store.radioReports.first.id, endsWith('000000000016'));
      expect(f.store.radioReports.last.id, endsWith('000000000003'));
      final before = jsonEncode(f.store.snapshot());
      final conflict = f.store.radioReports.last.toJson()
        ..['reason'] = 'disconnected';
      final incoming = f.store.backup()
        ..['radioReports'] = [
          conflict,
          for (var i = 100; i < 119; i++)
            session(
              id: '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
            ).finish('manual').toJson(),
        ];
      await expectLater(f.store.restore(incoming), throwsFormatException);
      expect(jsonEncode(f.store.snapshot()), before);
    } finally {
      await f.store.close();
      await f.root.delete(recursive: true);
    }
  });
}
