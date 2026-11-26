import 'dart:async';
import 'dart:typed_data';

import 'package:amid_offgrid/models/street_map.dart';
import 'package:amid_offgrid/services/street_http_client.dart';
import 'package:amid_offgrid/services/street_service.dart';
import 'package:amid_offgrid/services/atlas_storage.dart';
import 'package:amid_offgrid/services/backup_codec.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('planner bounds planet requests and deduplicates dateline tiles', () {
    expect(
      () => StreetBounds(-180, -85, 180, 85).tiles(15),
      throwsFormatException,
    );
    expect(() => StreetBounds(0, double.nan, 1, 1), throwsFormatException);
    expect(() => StreetTile.parse('15-32768-0'), throwsFormatException);
    final tiles = StreetBounds(179.999, 0, -179.999, .001).tiles(15);
    expect(tiles.map((t) => t.key).toSet().length, tiles.length);
    expect(tiles.where((t) => t.z == 0).length, 1);
    expect(tiles.where((t) => t.z == 15).map((t) => t.x).toSet(), {0, 32767});
  });

  test('planet HTTP rejects ignored ranges, wrong ranges, short bodies and changed versions', () async {
    for (final scenario in ['whole', 'wrong', 'short', 'large', 'version']) {
      var calls = 0;
      final client = StreetHttpClient(
        inner: MockClient((request) async {
          calls++;
          return http.Response.bytes(
            scenario == 'short'
                ? [1]
                : scenario == 'large'
                ? [1, 2, 3]
                : [1, 2],
            scenario == 'whole' ? 200 : 206,
            headers: {
              'content-range': scenario == 'wrong'
                  ? 'bytes 2-3/100'
                  : 'bytes 0-1/100',
              'etag': scenario == 'version' && calls > 1 ? 'b' : 'a',
            },
          );
        }),
      );
      try {
        if (scenario == 'version') {
          await client.get(
            Uri.parse(streetArchiveUrl),
            headers: {'Range': 'bytes=0-1'},
          );
        }
        await expectLater(
          client.get(
            Uri.parse(streetArchiveUrl),
            headers: {'Range': 'bytes=0-1'},
          ),
          throwsA(isA<http.ClientException>()),
        );
        final before = calls;
        await expectLater(
          client.get(
            Uri.parse('https://example.org/a'),
            headers: {'Range': 'bytes=0-1'},
          ),
          throwsA(isA<http.ClientException>()),
        );
        await expectLater(
          client.get(
            Uri.parse(streetArchiveUrl),
            headers: {'Range': 'bytes=0-9000000'},
          ),
          throwsA(isA<http.ClientException>()),
        );
        expect(calls, before);
      } finally {
        client.close();
      }
    }
  });

  test(
    'complete region survives service restart; corrupted bytes fail closed',
    () async {
      final f = await openTestStore();
      final storage = AtlasStorage(f.root.path, scope: 'streets');
      final bounds = StreetBounds(15.106, 50.058, 15.107, 50.059);
      final tiles = bounds.tiles(10);
      final bytes = Uint8List.fromList([1, 2, 3]);
      final service = StreetService(
        f.store,
        storage: storage,
        opener: (_) async => vt.MemoryVectorTileProvider(
          tiles: {for (final t in tiles) vt.TileKey(t.z, t.x, t.y): bytes},
          maximumZoom: 15,
        ),
      );
      StreetService? reopened;
      try {
        await service.download(bounds, 10, 'Велим');
        expect(f.store.streetRegions, hasLength(1));
        final region = f.store.streetRegions.single;
        expect(service.mode, region.id);
        final key = vt.TileKey(tiles.first.z, tiles.first.x, tiles.first.y);
        expect(await service.provider!.load(key), isA<vt.TileResponseData>());
        service.dispose();
        reopened = StreetService(
          f.store,
          storage: storage,
          opener: (_) async => throw StateError('must never access network'),
        );
        await reopened.selectMode(region.id);
        expect(await reopened.provider!.load(key), isA<vt.TileResponseData>());
        await storage.put(
          region.storageId(tiles.first.key),
          Uint8List.fromList([9, 9, 9]),
        );
        expect(await reopened.provider!.load(key), isA<vt.TileResponseError>());
        final bad = {...region.data, 'tiles': <String, dynamic>{}};
        expect(() => StreetRegion(bad), throwsFormatException);
        await reopened.delete(region);
        expect(f.store.streetRegions, isEmpty);
        expect(await storage.read(region.storageId(tiles.first.key)), isNull);
      } finally {
        if (reopened == null) {
          service.dispose();
        } else {
          reopened.dispose();
        }
        await f.store.close();
        await f.root.delete(recursive: true);
      }
    },
  );

  test(
    'cancelled region never commits partial data or changes chosen layer',
    () async {
      final f = await openTestStore();
      final pending = Completer<vt.VectorTileProvider>();
      final service = StreetService(f.store, opener: (_) => pending.future);
      try {
        final operation = service.download(
          StreetBounds(15.106, 50.058, 15.107, 50.059),
          10,
          'Cancelled',
        );
        final outcome = expectLater(
          operation,
          throwsA(isA<OperationCancelled>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        service.cancelDownload();
        pending.complete(
          vt.MemoryVectorTileProvider(tiles: {}, maximumZoom: 15),
        );
        await outcome;
        expect(f.store.streetRegions, isEmpty);
        expect(service.busy, isFalse);
        expect(service.mode, 'overview');
      } finally {
        service.dispose();
        await f.store.close();
        await f.root.delete(recursive: true);
      }
    },
  );
}
