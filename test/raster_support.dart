import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Uint8List rasterPng() => Uint8List.fromList(TileProvider.transparentImage);

Future<File> rasterFixture(
  Directory root, {
  String name = 'test.mbtiles',
  List<List<Object?>>? metadata,
  List<List<Object?>>? tiles,
  bool views = false,
}) async {
  final file = File('${root.path}/sources/$name');
  await file.parent.create(recursive: true);
  final db = await databaseFactoryFfi.openDatabase(file.path);
  final metaTable = views ? 'metadata_storage' : 'metadata';
  final tileTable = views ? 'tiles_storage' : 'tiles';
  try {
    await db.execute('CREATE TABLE $metaTable(name TEXT,value TEXT)');
    await db.execute(
      'CREATE TABLE $tileTable(zoom_level INTEGER,tile_column INTEGER,tile_row INTEGER,tile_data BLOB)',
    );
    for (final row
        in metadata ??
            <List<Object?>>[
              ['format', 'png'],
              ['name', 'Synthetic test tiles'],
            ]) {
      await db.insert(metaTable, {'name': row[0], 'value': row[1]});
    }
    for (final row
        in tiles ??
            <List<Object?>>[
              [0, 0, 0, rasterPng()],
            ]) {
      await db.insert(tileTable, {
        'zoom_level': row[0],
        'tile_column': row[1],
        'tile_row': row[2],
        'tile_data': row[3],
      });
    }
    if (views) {
      await db.execute(
        'CREATE VIEW metadata AS SELECT name,value FROM $metaTable',
      );
      await db.execute(
        'CREATE VIEW tiles AS SELECT zoom_level,tile_column,tile_row,tile_data FROM $tileTable',
      );
    }
  } finally {
    await db.close();
  }
  return file;
}
