import 'dart:io';
import 'dart:typed_data';

import 'package:amid_offgrid/models/raster_limits.dart';
import 'package:amid_offgrid/services/raster_archive_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'raster_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('amid-raster-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<RasterArchive> open(File file) =>
      RasterArchive.open(file.path, factory: databaseFactoryFfi);

  test(
    'read-only archive preserves bytes and derives center from a real tile',
    () async {
      final file = await rasterFixture(root);
      final before = await file.readAsBytes();
      final archive = await open(file);
      try {
        expect(await archive.readTile(0, 0, 0), rasterPng());
        expect(archive.info['center'], [0.0, 0.0, 0.0]);
        expect(archive.info['maxZoom'], 24);
      } finally {
        await archive.close();
      }
      expect(await file.readAsBytes(), before);
      expect(await archive.readTile(0, 0, 0), isNull);
      expect(identical(archive.close(), archive.close()), isTrue);
    },
  );

  test(
    'normalized views and TMS north/south coordinates are handled correctly',
    () async {
      final file = await rasterFixture(
        root,
        views: true,
        tiles: [
          [1, 0, 1, rasterPng()],
        ],
      );
      final archive = await open(file);
      try {
        expect(await archive.readTile(1, 0, 0), rasterPng());
        expect(await archive.readTile(1, 0, 1), isNull);
        final center = archive.info['center'] as List;
        expect(center[0], closeTo(66.513260443, 1e-6));
        expect(center[1], -90);
        expect(center[2], 1);
        for (final c in [
          (25, 0, 0),
          (-1, 0, 0),
          (1, -1, 0),
          (1, 2, 0),
          (1, 0, 2),
        ]) {
          expect(await archive.readTile(c.$1, c.$2, c.$3), isNull);
        }
      } finally {
        await archive.close();
      }
    },
  );

  final badMetadata = <String, List<List<Object?>>>{
    'duplicate': [
      ['format', 'png'],
      ['format', 'png'],
    ],
    'row limit': [
      ['format', 'png'],
      for (var i = 0; i < RasterLimits.metadataRows; i++) ['extra$i', 'value'],
    ],
    'name limit': [
      ['format', 'png'],
      ['x' * (RasterLimits.metadataNameBytes + 1), 'v'],
    ],
    'value limit': [
      ['format', 'png'],
      ['extra', 'x' * (RasterLimits.metadataValueBytes + 1)],
    ],
    'blob value': [
      ['format', 'png'],
      [
        'extra',
        Uint8List.fromList([1]),
      ],
    ],
    'empty name': [
      ['format', 'png'],
      ['', 'v'],
    ],
    'XYZ scheme': [
      ['format', 'png'],
      ['scheme', 'xyz'],
    ],
    'fractional zoom': [
      ['format', 'png'],
      ['minzoom', '1.5'],
    ],
  };
  for (final entry in badMetadata.entries) {
    test('reject metadata ${entry.key}', () async {
      final file = await rasterFixture(root, metadata: entry.value);
      await expectLater(open(file), throwsFormatException);
    });
  }

  for (final c in [(-1, 0, 0), (25, 0, 0), (1, 2, 0), (1, 0, 2)]) {
    test('reject invalid sample coordinate $c', () async {
      final file = await rasterFixture(
        root,
        tiles: [
          [c.$1, c.$2, c.$3, rasterPng()],
        ],
      );
      await expectLater(open(file), throwsFormatException);
    });
  }

  test('encoded byte cap applies to first and later tiles without poisoning the queue', () async {
    final file = await rasterFixture(
      root,
      tiles: [
        [0, 0, 0, rasterPng()],
        [1, 0, 0, rasterPng()],
      ],
    );
    final db = await databaseFactoryFfi.openDatabase(file.path);
    await db.rawUpdate(
      'UPDATE tiles SET tile_data=zeroblob(?) WHERE zoom_level=1',
      [RasterLimits.tileBytes + 1],
    );
    await db.close();
    final archive = await open(file);
    try {
      await expectLater(archive.readTile(1, 0, 1), throwsFormatException);
      expect(await archive.readTile(0, 0, 0), rasterPng());
      final pending = List.generate(20, (_) => archive.readTile(0, 0, 0));
      final closing = archive.close();
      expect(await Future.wait(pending), everyElement(isNull));
      await closing;
    } finally {
      await archive.close();
    }
    final writer = await databaseFactoryFfi.openDatabase(file.path);
    await writer.rawDelete('DELETE FROM tiles WHERE zoom_level=0');
    await writer.close();
    await expectLater(open(file), throwsFormatException);
  });

  test('duplicate coordinate records are rejected on lazy reads', () async {
    final file = await rasterFixture(
      root,
      tiles: [
        [0, 0, 0, rasterPng()],
        [1, 0, 0, rasterPng()],
        [1, 0, 0, rasterPng()],
      ],
    );
    final archive = await open(file);
    try {
      await expectLater(archive.readTile(1, 0, 1), throwsFormatException);
    } finally {
      await archive.close();
    }
  });

  test('empty archives and non-BLOB tile data are rejected', () async {
    await expectLater(
      open(await rasterFixture(root, name: 'empty.mbtiles', tiles: [])),
      throwsFormatException,
    );
    await expectLater(
      open(
        await rasterFixture(
          root,
          name: 'text.mbtiles',
          tiles: [
            [0, 0, 0, 'PNG'],
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test('missing paths do not create an empty database', () async {
    final file = File('${root.path}/missing.mbtiles');
    await expectLater(open(file), throwsA(isA<FileSystemException>()));
    expect(await file.exists(), isFalse);
  });
}
