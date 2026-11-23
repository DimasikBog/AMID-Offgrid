import 'dart:io';
import 'dart:typed_data';

import 'package:amid_offgrid/services/importer_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'raster_support.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  sqlite.databaseFactory = databaseFactoryFfi;

  test('valid map import stores checked metadata and removal deletes only its private copy', () async {
    final fixture = await openTestStore();
    final files = ImportService(fixture.store);
    try {
      final input = await rasterFixture(fixture.root);
      await files.importPath(input.path);
      final pack = fixture.store.packs.singleWhere((p) => p['kind'] == 'map');
      expect(pack['format'], 'png');
      expect(pack['center'], [0.0, 0.0, 0.0]);
      expect(pack['sha256'], hasLength(64));
      expect(fixture.store.selectedMap, pack['id']);
      final privateFile = File(pack['path'] as String);
      expect(await privateFile.exists(), isTrue);
      await fixture.store.removePack(pack['id'] as String);
      await files.deleteAsset(pack);
      expect(await privateFile.exists(), isFalse);
      expect(await input.exists(), isTrue);
    } finally {
      files.dispose();
      await fixture.store.close();
      await fixture.root.delete(recursive: true);
    }
  });

  test('import inspection rejects duplicate metadata instead of silently choosing a value', () async {
    final fixture = await openTestStore();
    final files = ImportService(fixture.store);
    try {
      final input = await rasterFixture(
        fixture.root,
        metadata: [
          ['format', 'png'],
          ['format', 'png'],
        ],
      );
      await expectLater(files.inspectMap(input.path), throwsFormatException);
    } finally {
      files.dispose();
      await fixture.store.close();
      await fixture.root.delete(recursive: true);
    }
  });

  test(
    'a non-image tile is rejected before its package is activated',
    () async {
      final fixture = await openTestStore();
      final files = ImportService(fixture.store);
      try {
        final input = await rasterFixture(
          fixture.root,
          tiles: [
            [
              0,
              0,
              0,
              Uint8List.fromList([1, 2, 3, 4]),
            ],
          ],
        );
        await expectLater(files.importPath(input.path), throwsFormatException);
        expect(fixture.store.packs.any((p) => p['kind'] == 'map'), isFalse);
        expect(
          await Directory('${fixture.root.path}/files').list().toList(),
          isEmpty,
        );
        expect(await input.exists(), isTrue);
      } finally {
        files.dispose();
        await fixture.store.close();
        await fixture.root.delete(recursive: true);
      }
    },
  );
}
