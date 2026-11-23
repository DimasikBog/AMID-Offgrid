import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:amid_offgrid/models/data.dart';
import 'package:amid_offgrid/services/backend_native.dart';
import 'package:amid_offgrid/services/store.dart';

Json pack(String id) => {
  'format': 'AMID_OFFGRID_PACK',
  'version': 1,
  'id': id,
  'title': 'Мої знання',
  'license': 'CC0',
  'articles': [
    {
      'id': 'one',
      'title': 'Мапа міста',
      'body': 'Офлайн карта і координати',
      'source': 'https://example.org/source',
    },
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late AppStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('amid-test-');
    store = await AppStore.open(
      backend: await PlatformBackend.open(
        factory: databaseFactoryFfi,
        root: root,
      ),
      seedText: File('assets/starter.json').readAsStringSync(),
    );
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });
  test(
    'SQLite persists offline content and Unicode FTS prefix search',
    () async {
      await store.importKnowledge(parsePack(pack('city')));
      expect((await store.search('мап')).single.title, 'Мапа міста');
      await store.savePin(const Pin('home', 'Дім', 50, 14));
      await store.setDraft('Зустріч тут');
      await store.close();
      store = await AppStore.open(
        backend: await PlatformBackend.open(
          factory: databaseFactoryFfi,
          root: root,
        ),
      );
      expect(store.pins.single.name, 'Дім');
      expect(store.draft, 'Зустріч тут');
      expect(
        (await store.search('координат')).any((a) => a.packId == 'city'),
        isTrue,
      );
    },
  );
  test(
    'failed FTS transaction rolls back in-memory and persisted state',
    () async {
      final before = jsonEncode(store.snapshot());
      await store.backend.db.execute('DROP TABLE article_search');
      await expectLater(
        store.importKnowledge(parsePack(pack('fail'))),
        throwsA(anything),
      );
      expect(jsonEncode(store.snapshot()), before);
      expect(jsonEncode(await store.backend.load()), before);
    },
  );
  test(
    'queue recovers from duplicate IDs without losing later writes',
    () async {
      await store.importKnowledge(parsePack(pack('unique')));
      await expectLater(
        store.importKnowledge(parsePack(pack('unique'))),
        throwsFormatException,
      );
      await store.savePin(const Pin('p', 'Місце', 48, 22));
      expect(store.pins.length, 1);
      expect(store.packs.where((p) => p['id'] == 'unique').length, 1);
    },
  );
  test(
    'invalid restore is atomic and backup excludes binary model paths',
    () async {
      final before = store.articles.length;
      await expectLater(
        store.restore({
          'format': 'AMID_OFFGRID_BACKUP',
          'version': 1,
          'packs': [pack('new')],
          'pins': [
            {'id': 'broken', 'name': 'X', 'latitude': 999, 'longitude': 0},
          ],
          'messages': [],
        }),
        throwsFormatException,
      );
      expect(store.articles.length, before);
      expect(store.packs.any((p) => p['id'] == 'new'), isFalse);
      await store.addAsset({
        'id': 'model',
        'kind': 'model',
        'path': '/private/model.gguf',
        'title': 'Test',
      });
      expect(
        jsonEncode(store.backup()).contains('/private/model.gguf'),
        isFalse,
      );
    },
  );
  test('knowledge, pins and delivery states survive portable backup', () async {
    await store.importKnowledge(parsePack(pack('saved')));
    await store.savePin(const Pin('a', 'Точка', 48.5, 22.5));
    await store.saveMessage(
      const Message('m', 'Привіт', '2026-11-22T10:00:00Z', 'out', 'delivered'),
    );
    final backup = store.backup();
    await store.removePack('saved');
    await store.restore(backup);
    expect(store.packs.any((p) => p['id'] == 'saved'), isTrue);
    expect(store.backup()['pins'], hasLength(1));
    final other = await Directory.systemTemp.createTemp('amid-restore-');
    final restored = await AppStore.open(
      backend: await PlatformBackend.open(
        factory: databaseFactoryFfi,
        root: other,
      ),
      seedText: File('assets/starter.json').readAsStringSync(),
    );
    try {
      await restored.restore(backup);
      expect(restored.messages.single.status, 'draft');
      expect(restored.pins.single.latitude, 48.5);
    } finally {
      await restored.close();
      await other.delete(recursive: true);
    }
  });
  test(
    'invalid package IDs, unsafe sources and geographic coordinates rejected',
    () {
      expect(
        () => parsePack({...pack('../escape'), 'id': '../escape'}),
        throwsFormatException,
      );
      final unsafe = pack('unsafe');
      (unsafe['articles'] as List).first['source'] = 'javascript:alert(1)';
      expect(() => parsePack(unsafe), throwsFormatException);
      expect(
        () => Pin.fromJson({
          'id': 'x',
          'name': 'x',
          'latitude': double.nan,
          'longitude': 0,
        }),
        throwsFormatException,
      );
      expect(
        () => validateGeoJson({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [190, 48],
              },
            },
          ],
        }),
        throwsFormatException,
      );
      final duplicate = pack('dupes');
      (duplicate['articles'] as List).add(
        (duplicate['articles'] as List).first,
      );
      expect(() => parsePack(duplicate), throwsFormatException);
    },
  );
}
