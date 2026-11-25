import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:amid_offgrid/models/catalog.dart';
import 'package:amid_offgrid/models/starter_content.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MetadataBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final encoded = switch (key) {
      'assets/catalog.json' => const String.fromEnvironment(
        'OFFGRID_CATALOG_BASE64',
      ),
      'assets/offline_model/catalog.json' => const String.fromEnvironment(
        'OFFGRID_STARTER_BASE64',
      ),
      _ => '',
    };
    if (encoded.isEmpty) {
      throw StateError(
        'Run web metadata tests with scripts/check_catalog_browser.py',
      );
    }
    return ByteData.sublistView(base64Decode(encoded));
  }
}

AssetBundle get metadataBundle =>
    kIsWeb || const String.fromEnvironment('OFFGRID_CATALOG_BASE64').isNotEmpty
    ? _MetadataBundle()
    : rootBundle;

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
    final items = await loadCatalog(bundle: metadataBundle);
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
  test(
    'multi-GiB model bounds also work when compiled to JavaScript',
    () async {
      final starter = await StarterCatalog.load(metadataBundle);
      expect(starter.model.bytes, greaterThan(600000000));
      final items = await loadCatalog(bundle: metadataBundle);
      final model = items.firstWhere((e) => e.bytes > 4000000000);
      expect(model.bytes, 4280404704);
      final metadata = {
        'id': 'bounds-model',
        'kind': 'model',
        'title': 'Bounds fixture',
        'description': 'Size validation only',
        'source': 'https://huggingface.co/',
        'license': 'Test fixture',
        'url': 'https://huggingface.co/fixture.gguf',
        'sha256': 'a' * 64,
        'bytes': 8589934592,
      };
      expect(CatalogEntry.fromJson(metadata).bytes, 8589934592);
      expect(
        () => CatalogEntry.fromJson({...metadata, 'bytes': 8589934593}),
        throwsFormatException,
      );
    },
  );
}
