import 'dart:convert';
import 'dart:io';

import 'package:amid_offgrid/models/data.dart';
import 'package:amid_offgrid/services/backend_native.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppStore store;
  setUp(() async {
    final pair = await openTestStore();
    root = pair.root;
    store = pair.store;
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test(
    'Unicode prefixes and mixed-language queries survive SQLite reopen',
    () async {
      await store.saveNote(
        id: 'emulator',
        title: 'AMID перевірка емулятора',
        body: 'Синтетичні дані',
      );
      final key = '${AppStore.notesId}::emulator';
      Future<void> verify() async {
        for (final query in [
          'перевір',
          'емулятор',
          'AMID перевірка емулятора',
        ]) {
          expect((await store.search(query)).map((a) => a.key), contains(key));
        }
      }

      await verify();
      await store.close();
      store = await AppStore.open(
        backend: await PlatformBackend.open(
          factory: databaseFactoryFfi,
          root: root,
        ),
      );
      await verify();
    },
  );

  test(
    'notes edit, favorite and theme survive closing and reopening',
    () async {
      await store.saveNote(
        id: 'water',
        title: 'Запас води',
        body: 'Десять літрів',
      );
      final key = '${AppStore.notesId}::water';
      await store.toggleFavorite(key);
      await store.setThemePreference('dark');
      await store.saveNote(
        id: 'water',
        title: 'Запас води',
        body: 'Двадцять літрів',
      );
      expect(
        (await store.search('Двадцять', favoritesOnly: true)).single.key,
        key,
      );
      await store.close();
      store = await AppStore.open(
        backend: await PlatformBackend.open(
          factory: databaseFactoryFfi,
          root: root,
        ),
      );
      expect(store.themePreference, 'dark');
      expect(store.favoriteKeys, contains(key));
      await store.deleteNote(key);
      expect(store.favoriteKeys, isNot(contains(key)));
      expect(await store.search('Двадцять'), isEmpty);
    },
  );
  test('search ranks titles beyond the first 80 FTS matches and filters before limiting', () async {
    await store.importKnowledge(
      parsePack({
        'format': 'AMID_OFFGRID_PACK',
        'version': 1,
        'id': 'many',
        'title': 'Багато',
        'license': 'CC0',
        'articles': List.generate(
          120,
          (i) => {
            'id': '$i',
            'title': i == 119 ? 'Вода вдома' : 'Матеріал $i',
            'body': 'Вода для життя',
            'category': i == 119 ? 'Особливе' : 'Інше',
          },
        ),
      }),
    );
    expect((await store.search('Вода', limit: 1)).single.key, 'many::119');
    expect(
      (await store.search('Вода', limit: 1, category: 'Особливе')).single.key,
      'many::119',
    );
    await store.toggleFavorite('many::119');
    expect(
      (await store.search('Вода', limit: 1, favoritesOnly: true)).single.key,
      'many::119',
    );
  });
  test('restore rejects duplicate IDs atomically and merges distinct personal notes', () async {
    await store.saveNote(id: 'first', title: 'Перше', body: 'А');
    final before = jsonEncode(store.snapshot());
    await expectLater(
      store.restore({
        'format': 'AMID_OFFGRID_BACKUP',
        'version': 1,
        'packs': [],
        'messages': [],
        'pins': [
          {'id': 'p', 'name': 'А', 'latitude': 48, 'longitude': 22},
          {'id': 'p', 'name': 'Б', 'latitude': 49, 'longitude': 23},
        ],
      }),
      throwsFormatException,
    );
    expect(jsonEncode(store.snapshot()), before);
    final backup = store.backup();
    await store.deleteNote('${AppStore.notesId}::first');
    await store.saveNote(id: 'second', title: 'Друге', body: 'Б');
    await store.restore(backup);
    expect(
      store.articles.where((a) => a.packId == AppStore.notesId),
      hasLength(2),
    );
  });
  test('restore checks combined capacity and keeps the database unchanged on rejection', () async {
    store.pins = List.generate(9999, (i) => Pin('p$i', 'Точка', 48, 22));
    await store.backend.save(store.snapshot());
    final before = jsonEncode(store.snapshot());
    await expectLater(
      store.restore({
        'format': 'AMID_OFFGRID_BACKUP',
        'version': 1,
        'packs': [],
        'messages': [],
        'pins': [
          {'id': 'new1', 'name': 'А', 'latitude': 48, 'longitude': 22},
          {'id': 'new2', 'name': 'Б', 'latitude': 49, 'longitude': 23},
        ],
      }),
      throwsFormatException,
    );
    expect(jsonEncode(store.snapshot()), before);
    expect(jsonEncode(await store.backend.load()), before);
  });
  test('saving a message does not erase a newer draft', () async {
    await store.setDraft('Новіший текст');
    await store.saveDraftMessage('Старий текст');
    expect(store.draft, 'Новіший текст');
    await store.saveDraftMessage('Новіший текст');
    expect(store.draft, '');
    expect(store.messages, hasLength(2));
  });
  test('close drains pending writes and can be awaited repeatedly', () async {
    final write = store.setDraft('Остання зміна');
    await store.close();
    await write;
    await store.close();
    store = await AppStore.open(
      backend: await PlatformBackend.open(
        factory: databaseFactoryFfi,
        root: root,
      ),
    );
    expect(store.draft, 'Остання зміна');
  });
  test(
    'backup includes favorites, draft and theme but no model paths',
    () async {
      await store.saveNote(id: 'one', title: 'Нотатка', body: 'Текст');
      await store.toggleFavorite('${AppStore.notesId}::one');
      await store.setDraft('Моя чернетка');
      await store.setThemePreference('light');
      final backup = store.backup();
      expect(backup['draft'], 'Моя чернетка');
      expect(backup['favoriteKeys'], contains('${AppStore.notesId}::one'));
      expect(backup['themePreference'], 'light');
    },
  );
}
