import 'dart:async';
import 'dart:convert';

import 'package:amid_offgrid/models/catalog.dart';
import 'package:amid_offgrid/services/catalog_service.dart';
import 'package:amid_offgrid/services/importer.dart';
import 'package:amid_offgrid/services/backup_codec.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support.dart';
import 'raster_image_fixtures.dart';

CatalogEntry fixture(
  List<int> bytes, {
  String kind = 'geojson',
  String? hash,
}) => CatalogEntry.fromJson({
  'id': 'fixture-map',
  'kind': kind,
  'title': 'Fixture only',
  'description': 'Synthetic validation data, not a real map.',
  'url': 'https://upload.wikimedia.org/fixture',
  'source': 'https://commons.wikimedia.org/',
  'bytes': bytes.length,
  'sha256': hash ?? sha256.convert(bytes).toString(),
  'license': 'Synthetic test fixture',
});
final geo = utf8.encode(
  jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {'name': 'Fixture'},
        'geometry': {
          'type': 'Point',
          'coordinates': [15, 50],
        },
      },
    ],
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('catalogue rejects unsafe download origins, credentials, hashes and resource bounds', () {
    final good = {
      'id': 'valid-map',
      'kind': 'image',
      'title': 'Title',
      'description': 'Description',
      'source': 'https://commons.wikimedia.org/',
      'license': 'Public domain',
      'url': 'https://upload.wikimedia.org/a.jpg',
      'bytes': 100,
      'sha256': 'a' * 64,
    };
    for (final change in [
      {'url': 'http://upload.wikimedia.org/a.jpg'},
      {'url': 'https://localhost/a.jpg'},
      {'url': 'https://name:password@upload.wikimedia.org/a.jpg'},
      {'bytes': 17 << 20},
      {'sha256': 'missing'},
      {'kind': 'executable'},
      {'id': '../escape'},
    ]) {
      expect(
        () => CatalogEntry.fromJson({...good, ...change}),
        throwsFormatException,
      );
    }
    expect(CatalogEntry.fromJson(good).installable, isTrue);
  });
  test('bundled catalogue has verified map installs, sources and four pinned official models', () async {
    final items = await loadCatalog();
    expect(items.where((e) => e.model).length, 4);
    expect(items.where((e) => e.kind == 'image').length, 3);
    expect(items.where((e) => e.kind == 'geojson').length, 3);
    for (final item in items.where((e) => e.model)) {
      expect(item.url!.path, contains(RegExp(r'/resolve/[a-f0-9]{40}/')));
      expect(item.source, startsWith('https://huggingface.co/Qwen/'));
    }
    expect(
      items.where((e) => e.kind == 'source').every((e) => !e.installable),
      isTrue,
    );
  });
  test('verified GeoJSON is persisted, repeat install is idempotent, hash corruption is rejected', () async {
    final f = await openTestStore();
    final files = ImportService(f.store);
    var calls = 0;
    final entry = fixture(geo);
    final service = CatalogService(
      f.store,
      files,
      catalogue: Future.value([entry]),
      clientFactory: () => MockClient((request) async {
        calls++;
        return http.Response.bytes(geo, 200);
      }),
    );
    await service.install(entry);
    await service.install(entry);
    expect(calls, 1);
    expect(service.installed(entry), isTrue);
    expect(
      f.store.packs.singleWhere((p) => p['id'] == entry.id)['map'],
      isNotNull,
    );
    service.dispose();
    files.dispose();
    await f.store.close();
    await f.root.delete(recursive: true);
    final badFixture = await openTestStore();
    final badFiles = ImportService(badFixture.store);
    final bad = fixture(geo, hash: 'a' * 64);
    final reject = CatalogService(
      badFixture.store,
      badFiles,
      catalogue: Future.value([bad]),
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes(geo, 200)),
    );
    await expectLater(reject.install(bad), throwsFormatException);
    expect(reject.installed(bad), isFalse);
    reject.dispose();
    badFiles.dispose();
    await badFixture.store.close();
    await badFixture.root.delete(recursive: true);
  });
  test('operation is claimed before catalogue resolution; cancellation discards late responses', () async {
    final f = await openTestStore();
    final files = ImportService(f.store);
    final entry = fixture(geo);
    final catalogue = Completer<List<CatalogEntry>>(),
        response = Completer<http.Response>();
    final service = CatalogService(
      f.store,
      files,
      catalogue: catalogue.future,
      clientFactory: () => MockClient((_) => response.future),
    );
    final first = service.install(entry);
    final completion = expectLater(first, throwsA(isA<OperationCancelled>()));
    await expectLater(service.install(entry), throwsStateError);
    catalogue.complete([entry]);
    await Future<void>.delayed(Duration.zero);
    service.cancel();
    response.complete(http.Response.bytes(geo, 200));
    await completion;
    expect(service.installed(entry), isFalse);
    service.dispose();
    files.dispose();
    await f.store.close();
    await f.root.delete(recursive: true);
  });
  testWidgets(
    'atlas image survives service recreation and is integrity checked when opened',
    (tester) async {
      final f = (await tester.runAsync(openTestStore))!;
      final files = ImportService(f.store);
      final bytes = base64Decode(rasterImageFixtures['jpeg']!);
      final entry = fixture(bytes, kind: 'image');
      final service = CatalogService(
        f.store,
        files,
        catalogue: Future.value([entry]),
        clientFactory: () =>
            MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      await tester.runAsync(() => service.install(entry));
      expect(service.installed(entry), isTrue);
      final reopened = CatalogService(
        f.store,
        files,
        catalogue: Future.value([entry]),
      );
      expect(await tester.runAsync(() => reopened.image(entry)), bytes);
      await tester.runAsync(() => reopened.remove(entry));
      expect(service.installed(entry), isFalse);
      await tester.runAsync(() async {
        service.dispose();
        reopened.dispose();
        files.dispose();
        await f.store.close();
        await f.root.delete(recursive: true);
      });
    },
  );
}
