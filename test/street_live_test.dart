// Opt-in public-data smoke check; normal CI never depends on a map server.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:amid_offgrid/models/street_map.dart';
import 'package:amid_offgrid/services/street_http_client.dart';
import 'package:amid_offgrid/services/street_service.dart';

import 'support.dart';

import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real complete region downloads every scale and reopens without network',
    () async {
      final f = await openTestStore();
      final streets = StreetService(
        f.store,
        clientFactory: () =>
            HttpOverrides.runWithHttpOverrides(http.Client.new, _LiveHttp()),
      );
      try {
        await streets.download(
          StreetBounds(15.1116, 50.0606, 15.1117, 50.0607),
          15,
          'Live smoke Velim',
        );
        final region = f.store.streetRegions.single;
        expect(streets.mode, region.id);
        expect(region.bytes, greaterThan(0));
        final tile = region.bounds.tiles(15).singleWhere((t) => t.z == 15);
        final provider = SavedStreetProvider(region, streets.storage);
        expect(
          await provider.load(vt.TileKey(tile.z, tile.x, tile.y)),
          isA<vt.TileResponseData>(),
        );
        provider.dispose();
        debugPrint(
          'Complete region: ${region.tileKeys.length} tiles, ${region.bytes} bytes',
        );
      } finally {
        streets.dispose();
        await f.store.close();
        await f.root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: Platform.environment['AMID_LIVE_MAP'] != '1',
  );
  test(
    'real PMTiles exact ranges yield street data',
    () async {
      final client = StreetHttpClient(
        inner: HttpOverrides.runWithHttpOverrides(http.Client.new, _LiveHttp()),
      );
      vt.VectorTileProvider? source;
      try {
        source = await vt.PmTilesVectorTileProvider.open(
          streetArchiveUrl,
          client: client,
          maxRetries: 0,
        );
        final dir = Directory(
          Platform.environment['AMID_MAP_EVIDENCE'] ??
              '${Directory.systemTemp.path}/amid-map-evidence',
        );
        await dir.create(recursive: true);
        for (var x = 17758; x <= 17760; x++) {
          for (var y = 11103; y <= 11104; y++) {
            final response = await source.load(vt.TileKey(15, x, y));
            expect(response, isA<vt.TileResponseData>());
            await File('${dir.path}/15-$x-$y.pbf')
                .writeAsBytes((response as vt.TileResponseData).bytes);
          }
        }
        expect(client.etag, isNotEmpty);
        debugPrint('Verified PMTiles ranges; snapshot ${client.dataDate}');
      } finally {
        source?.dispose();
        client.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: Platform.environment['AMID_LIVE_MAP'] != '1',
  );
}

// Use the normal TLS-verifying client only for this explicit public-data test.
class _LiveHttp extends HttpOverrides {}
