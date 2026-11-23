import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../models/data.dart';
import '../models/map_metadata.dart';
import '../models/raster_limits.dart';
import 'raster_codec_native.dart';

/// Read-only MBTiles access. Result sizes are bounded in SQL before crossing
/// the platform channel; the same checks apply to every subsequently read tile.
class RasterArchive {
  RasterArchive._(this._db, this.info, this.format);
  final Database _db;
  final Json info;
  final String format;
  bool _closed = false;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  bool get isClosed => _closed;

  static Future<RasterArchive> open(
    String path, {
    DatabaseFactory? factory,
  }) async {
    if (!await File(path).exists()) {
      throw const FileSystemException('Файл карти не знайдено.');
    }
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final rows = await db.rawQuery('''
        SELECT CASE WHEN typeof(name)='text' AND length(CAST(name AS BLOB)) BETWEEN 1 AND ${RasterLimits.metadataNameBytes}
                    THEN name ELSE NULL END AS name,
               CASE WHEN typeof(value)='text' AND length(CAST(value AS BLOB)) <= ${RasterLimits.metadataValueBytes}
                    THEN value ELSE NULL END AS value
        FROM metadata LIMIT ${RasterLimits.metadataRows + 1}
      ''');
      if (rows.length > RasterLimits.metadataRows) {
        throw const FormatException(
          'Забагато метаданих MBTiles: ліміт 128 рядків.',
        );
      }
      final metadata = <String, String>{};
      for (final row in rows) {
        final name = row['name'], value = row['value'];
        if (name is! String || value is! String || metadata.containsKey(name)) {
          throw const FormatException(
            'Повторювані, завеликі або некоректні метадані MBTiles.',
          );
        }
        metadata[name] = value;
      }
      metadata['format'] = metadata['format']?.trim().toLowerCase() ?? '';
      final sample = await db.rawQuery(
        'SELECT zoom_level,tile_column,tile_row FROM tiles LIMIT 1',
      );
      if (sample.isEmpty) {
        throw const FormatException('Карта не містить тайлів.');
      }
      final z = sample.first['zoom_level'],
          x = sample.first['tile_column'],
          tmsY = sample.first['tile_row'];
      if (z is! int ||
          x is! int ||
          tmsY is! int ||
          !validCoordinates(z, x, tmsY)) {
        throw const FormatException('Некоректні координати тайла MBTiles.');
      }
      final y = (1 << z) - 1 - tmsY;
      if (!metadata.containsKey('center') && !metadata.containsKey('bounds')) {
        final scale = (1 << z).toDouble();
        final lon = (x + .5) / scale * 360 - 180;
        final n = math.pi * (1 - 2 * (y + .5) / scale);
        final lat = math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
        metadata['center'] = '$lon,$lat,$z';
      }
      final info = {
        ...parseRasterMapMetadata(metadata),
        'format': metadata['format'],
      };
      final archive = RasterArchive._(
        db,
        Map.unmodifiable(info),
        metadata['format']!,
      );
      final bytes = await archive.readTile(z, x, y);
      if (bytes == null) {
        throw const FormatException('Тайл зразка не знайдено.');
      }
      await verifyRasterSample(bytes, archive.format);
      return archive;
    } catch (error) {
      await db.close();
      if (error is FormatException || error is FileSystemException) rethrow;
      throw FormatException('Не вдалося перевірити MBTiles: $error');
    }
  }

  static bool validCoordinates(int z, int x, int y) =>
      z >= 0 &&
      z <= RasterLimits.zoom &&
      x >= 0 &&
      y >= 0 &&
      x < (1 << z) &&
      y < (1 << z);

  Future<Uint8List?> readTile(int z, int x, int y) {
    if (_closed || !validCoordinates(z, x, y)) return Future.value(null);
    final job = _tail.then<Uint8List?>((_) async {
      if (_closed) return null;
      final rows = await _db.rawQuery(
        '''
        SELECT CASE WHEN typeof(tile_data)='blob' AND length(tile_data) BETWEEN 1 AND ${RasterLimits.tileBytes}
                    THEN tile_data ELSE NULL END AS data
        FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=? LIMIT 2
      ''',
        [z, x, (1 << z) - 1 - y],
      );
      if (_closed || rows.isEmpty) return null;
      if (rows.length != 1 || rows.single['data'] is! Uint8List) {
        throw const FormatException(
          'Повторюваний, порожній або завеликий тайл MBTiles.',
        );
      }
      return rows.single['data'] as Uint8List;
    });
    _tail = job.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return job;
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = _tail.then((_) => _db.close());
  }
}
