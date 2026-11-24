import 'dart:io';

import 'package:amid_offgrid/services/backend_native.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reader scale and personal preparation survive reopen and backup restore',
    () async {
      final a = await openTestStore(), b = await openTestStore();
      AppStore? reopened;
      try {
        await a.store.setReaderScale(1.4);
        await a.store.setPrepared('backup', true);
        await a.store.setPrepared('water', true);
        await a.store.setPrepared('water', false);
        final backup = a.store.backup();
        await b.store.restore(backup);
        expect(b.store.readerScale, 1.4);
        expect(b.store.preparation, {'backup'});
        await a.store.close();
        reopened = await AppStore.open(
          backend: await PlatformBackend.open(root: a.root),
        );
        expect(reopened.readerScale, 1.4);
        expect(reopened.preparation, {'backup'});
      } finally {
        await a.store.close();
        await reopened?.close();
        await b.store.close();
        await a.root.delete(recursive: true);
        await b.root.delete(recursive: true);
      }
    },
  );
  test(
    'malformed optional preferences reject a restore before mutation',
    () async {
      final f = await openTestStore();
      try {
        final before = f.store.snapshot();
        for (final fields in [
          {'readerScale': double.nan},
          {'readerScale': double.infinity},
          {'readerScale': .79},
          {'readerScale': 1.81},
          {'readerScale': '1.2'},
          {
            'preparation': ['water', 'water'],
          },
          {
            'preparation': ['unknown'],
          },
          {'preparation': false},
        ]) {
          await expectLater(
            f.store.restore({...f.store.backup(), ...fields}),
            throwsFormatException,
          );
          expect(f.store.snapshot(), before);
        }
        await expectLater(
          f.store.setPrepared('unknown', true),
          throwsFormatException,
        );
        expect(f.store.snapshot(), before);
        await f.store.setReaderScale(.8);
        await f.store.setReaderScale(1.8);
      } finally {
        await f.store.close();
        await f.root.delete(recursive: true);
      }
    },
  );
  test(
    'legacy backup does not overwrite preferences waiting in the write queue',
    () async {
      final f = await openTestStore();
      try {
        final old = f.store.backup()
          ..remove('readerScale')
          ..remove('preparation')
          ..remove('themePreference');
        final writes = [
          f.store.setReaderScale(1.5),
          f.store.setPrepared('offline', true),
          f.store.setThemePreference('dark'),
        ];
        await f.store.restore(old);
        await Future.wait(writes);
        expect(f.store.readerScale, 1.5);
        expect(f.store.preparation, {'offline'});
        expect(f.store.themePreference, 'dark');
      } finally {
        await f.store.close();
        await f.root.delete(recursive: true);
      }
    },
  );
  test('default desktop database factory can save and reopen without a mobile channel', () async {
    final root = await Directory.systemTemp.createTemp('amid-default-db-');
    PlatformBackend? db;
    try {
      db = await PlatformBackend.open(root: root);
      await db.save({'articles': [], 'sample': 'native desktop'});
      await db.close();
      db = await PlatformBackend.open(root: root);
      expect((await db.load())?['sample'], 'native desktop');
    } finally {
      await db?.close();
      await root.delete(recursive: true);
    }
  });
}
