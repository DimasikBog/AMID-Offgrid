// Run explicitly through scripts/check_catalog_browser.py in isolated Chromium.
import 'dart:convert';
import 'dart:typed_data';

import 'package:amid_offgrid/models/street_map.dart';
import 'package:amid_offgrid/services/atlas_storage.dart';
import 'package:amid_offgrid/services/street_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('IndexedDB street bytes survive reopen, stay separate from atlas and reject corruption', () async {
    final bytes = base64Decode(
      const String.fromEnvironment('OFFGRID_STREET_TILE_BASE64'),
    );
    expect(bytes, isNotEmpty);
    final bounds = StreetBounds(15.1116, 50.0606, 15.1117, 50.0607);
    final tiles = bounds.tiles(15);
    final data = <String, dynamic>{
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'title': 'Browser fixture',
      'source': streetArchiveUrl,
      'bounds': bounds.json,
      'maxZoom': 15,
      'createdAt': '2026-11-26T00:00:00Z',
      'bytes': bytes.length,
      'tiles': {
        for (final t in tiles)
          t.key: {
            'bytes': t.z == 15 ? bytes.length : 0,
            'sha256': sha256
                .convert(t.z == 15 ? bytes : Uint8List(0))
                .toString(),
          },
      },
    };
    final region = StreetRegion(data);
    final key = tiles.singleWhere((t) => t.z == 15);
    final id = region.storageId(key.key);
    var streets = AtlasStorage('', scope: 'streets');
    final atlas = AtlasStorage('');
    try {
      await atlas.put('browser-atlas', Uint8List.fromList([7]));
      await streets.put(id, bytes);
      await streets.put('browser-orphan', Uint8List.fromList([8]));
      await streets.prune({id});
      expect(await streets.read('browser-orphan'), isNull);
      expect(await atlas.read('browser-atlas'), [7]);
      streets.dispose();
      streets = AtlasStorage('', scope: 'streets');
      final provider = SavedStreetProvider(region, streets);
      final tile = vt.TileKey(key.z, key.x, key.y);
      final first = await provider.load(tile);
      expect(first, isA<vt.TileResponseData>());
      expect((first as vt.TileResponseData).bytes, bytes);
      await streets.put(id, Uint8List.fromList([1, 2, 3]));
      expect(await provider.load(tile), isA<vt.TileResponseError>());
      provider.dispose();
    } finally {
      await streets.delete(id);
      await atlas.delete('browser-atlas');
      streets.dispose();
      atlas.dispose();
    }
  });
  test('JavaScript tile planning rejects planet-sized selections and handles the dateline', () {
    expect(
      () => StreetBounds(-180, -85, 180, 85).tiles(15),
      throwsFormatException,
    );
    final tiles = StreetBounds(179.999, 0, -179.999, .001).tiles(15);
    expect(tiles.map((t) => t.key).toSet().length, tiles.length);
    expect(tiles.where((t) => t.z == 15).map((t) => t.x).toSet(), {0, 32767});
  });
}
