import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../models/data.dart';

class PlatformBackend {
  PlatformBackend._(this.db, this.directory);
  final Database db;
  final String directory;
  static Future<PlatformBackend> open({
    DatabaseFactory? factory,
    Directory? root,
  }) async {
    final dir =
        root ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'offgrid'),
        );
    await dir.create(recursive: true);
    if (Platform.isIOS) {
      await const MethodChannel('com.amid.offgrid/files')
          .invokeMethod<void>('excludeFromBackup', {'path': dir.path});
    }
    final db = await (factory ?? databaseFactory).openDatabase(
      p.join(dir.path, 'offgrid.sqlite'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE state(id INTEGER PRIMARY KEY,value TEXT NOT NULL)',
          );
          try {
            await db.execute(
              'CREATE VIRTUAL TABLE article_search USING fts4(key,title,body,tokenize=unicode61)',
            );
          } on DatabaseException {
            await db.execute(
              'CREATE VIRTUAL TABLE article_search USING fts5(key UNINDEXED,title,body,tokenize=unicode61)',
            );
          }
        },
      ),
    );
    return PlatformBackend._(db, dir.path);
  }

  Future<Json?> load() async {
    final rows = await db.query('state', where: 'id=1');
    return rows.isEmpty ? null : decodeObject(rows.first['value'] as String);
  }

  Future<void> save(Json value, {bool reindex = false}) async {
    final encoded = jsonEncode(value);
    if (utf8.encode(encoded).length > 64 * 1024 * 1024) {
      throw const FormatException(
        'Ліміт текстових даних цієї версії — 64 MiB. Моделі й карти зберігаються окремо.',
      );
    }
    await db.transaction((tx) async {
      await tx.insert('state', {
        'id': 1,
        'value': encoded,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (reindex) {
        await tx.delete('article_search');
        final batch = tx.batch();
        for (final a in value['articles'] as List) {
          batch.insert('article_search', {
            'key': a['key'],
            'title': a['title'],
            'body': a['body'],
          });
        }
        await batch.commit(noResult: true);
      }
    });
  }

  Future<List<String>> searchKeys(String query, int limit) async {
    final terms = searchTerms(query);
    if (terms.isEmpty) return [];
    final rows = await db.rawQuery(
      'SELECT key FROM article_search WHERE article_search MATCH ? LIMIT ?',
      [terms.map((t) => '"$t"*').join(' OR '), limit],
    );
    return rows.map((r) => r['key'] as String).toList();
  }

  Future<void> close() => db.close();
}
