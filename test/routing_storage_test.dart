import 'dart:convert';
import 'dart:io';

import 'package:amid_offgrid/models/data.dart';
import 'package:amid_offgrid/models/route_network.dart';
import 'package:amid_offgrid/services/backend_native.dart';
import 'package:amid_offgrid/services/importer_native.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('upgrading bundled guidance preserves notes, pins and favorites and is idempotent', () async {
    final fixture = await openTestStore();
    var store = fixture.store;
    try {
      await store.saveNote(title: 'Особисте', body: 'Залишити мої дані');
      await store.savePin(const Pin('home', 'Дім', 48, 22));
      const key = '${AppStore.starterId}::privacy';
      await store.toggleFavorite(key);
      final legacy = store.snapshot();
      (legacy['packs'] as List)
          .firstWhere((p) => p['id'] == AppStore.starterId)
          .remove('bundledRevision');
      (legacy['articles'] as List).firstWhere((a) => a['key'] == key)['body'] =
          'Стара довідка';
      await store.backend.save(legacy, reindex: true);
      await store.close();
      store = await AppStore.open(
        backend: await PlatformBackend.open(
          factory: databaseFactoryFfi,
          root: fixture.root,
        ),
        seedText: File('assets/starter.json').readAsStringSync(),
      );
      expect(
        store.articles.singleWhere((a) => a.key == key).body,
        contains('AES-256-GCM'),
      );
      expect(
        store.articles.singleWhere((a) => a.packId == AppStore.notesId).body,
        'Залишити мої дані',
      );
      expect(store.pins.single.name, 'Дім');
      expect(store.favoriteKeys, contains(key));
      final refreshed = jsonEncode(store.snapshot());
      await store.close();
      store = await AppStore.open(
        backend: await PlatformBackend.open(
          factory: databaseFactoryFfi,
          root: fixture.root,
        ),
      );
      expect(jsonEncode(store.snapshot()), refreshed);
    } finally {
      await store.close();
      await fixture.root.delete(recursive: true);
    }
  });
  test('file import, SQLite reopen and portable restore preserve routable geometry', () async {
    final fixture = await openTestStore();
    var store = fixture.store;
    final files = ImportService(store);
    try {
      await files.importPath('examples/route_network.json');
      final pack = store.packs.last;
      final original = jsonEncode(pack['routing']);
      expect(pack['sha256'], hasLength(64));
      await store.close();
      store = await AppStore.open(
        backend: await PlatformBackend.open(
          factory: databaseFactoryFfi,
          root: fixture.root,
        ),
      );
      expect(jsonEncode(store.packs.last['routing']), original);
      final backup = store.backup();
      await store.removePack(pack['id'] as String);
      await store.restore(backup);
      expect(jsonEncode(store.packs.last['routing']), original);
      expect(
        RouteNetwork.parse(store.packs.last['routing'])
            .shortestPath('a', 'c')
            .legs,
        hasLength(2),
      );
    } finally {
      files.dispose();
      await store.close();
      await fixture.root.delete(recursive: true);
    }
  });

  test('an invalid route in a restore does not partially write other incoming data', () async {
    final fixture = await openTestStore();
    try {
      final before = jsonEncode(fixture.store.snapshot());
      final pack = decodeObject(
        File('examples/route_network.json').readAsStringSync(),
      );
      pack['routing']['edges'][0]['to'] = 'missing-node';
      final backup = fixture.store.backup();
      (backup['packs'] as List).add(pack);
      await expectLater(fixture.store.restore(backup), throwsFormatException);
      expect(jsonEncode(fixture.store.snapshot()), before);
      expect(jsonEncode(await fixture.store.backend.load()), before);
    } finally {
      await fixture.store.close();
      await fixture.root.delete(recursive: true);
    }
  });
}
