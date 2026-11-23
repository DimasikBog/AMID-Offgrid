import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amid_offgrid/models/raster_limits.dart';
import 'package:amid_offgrid/services/raster_archive_native.dart';
import 'package:amid_offgrid/widgets/raster_tile_provider_native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'raster_image_fixtures.dart';
import 'raster_support.dart';

Future<({int width, int height})> imageSize(ImageProvider provider) async {
  final done = Completer<({int width, int height})>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      final size = (width: image.image.width, height: image.image.height);
      image.dispose();
      stream.removeListener(listener);
      done.complete(size);
    },
    onError: (Object error, StackTrace? stack) {
      stream.removeListener(listener);
      done.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return done.future.timeout(const Duration(seconds: 5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('amid-provider-');
  });
  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await root.delete(recursive: true);
  });

  test(
    'image keys are stable within an archive and are evicted on provider close',
    () async {
      final file = await rasterFixture(root);
      final archive = await RasterArchive.open(
        file.path,
        factory: databaseFactoryFfi,
      );
      final provider = RasterTileProvider(
        archive,
        onIssue: (error) => fail('$error'),
      );
      try {
        final layer = TileLayer(tileProvider: provider);
        final image = provider.getImage(const TileCoordinates(0, 0, 0), layer);
        final same = provider.getImage(const TileCoordinates(0, 0, 0), layer);
        final key = await image.obtainKey(ImageConfiguration.empty);
        expect(await same.obtainKey(ImageConfiguration.empty), key);
        expect(await imageSize(image), (width: 1, height: 1));
        expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
        await provider.close();
        expect(archive.isClosed, isTrue);
        expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
        expect(
          await imageSize(
            provider.getImage(const TileCoordinates(0, 0, 0), layer),
          ),
          (width: 1, height: 1),
        );
      } finally {
        await provider.close();
      }
      final second = await RasterArchive.open(
        file.path,
        factory: databaseFactoryFfi,
      );
      final other = RasterTileProvider(second, onIssue: (_) {});
      try {
        expect(
          provider.getImage(
            const TileCoordinates(0, 0, 0),
            TileLayer(tileProvider: provider),
          ),
          isNot(
            other.getImage(
              const TileCoordinates(0, 0, 0),
              TileLayer(tileProvider: other),
            ),
          ),
        );
      } finally {
        await other.close();
      }
    },
  );

  test(
    'a bad lazy tile becomes transparent and does not break a good tile',
    () async {
      final file = await rasterFixture(
        root,
        tiles: [
          [0, 0, 0, rasterPng()],
          [1, 0, 0, base64Decode(rasterImageFixtures['jpeg']!)],
        ],
      );
      final archive = await RasterArchive.open(
        file.path,
        factory: databaseFactoryFfi,
      );
      final issues = <Object>[];
      final provider = RasterTileProvider(archive, onIssue: issues.add);
      try {
        final layer = TileLayer(tileProvider: provider);
        expect(
          await imageSize(
            provider.getImage(const TileCoordinates(0, 1, 1), layer),
          ),
          (width: 1, height: 1),
        );
        expect(issues.single, isA<FormatException>());
        expect(
          await imageSize(
            provider.getImage(const TileCoordinates(0, 0, 0), layer),
          ),
          (width: 1, height: 1),
        );
        expect(
          await imageSize(
            provider.getImage(const TileCoordinates(1, 1, 1), layer),
          ),
          (width: 1, height: 1),
        );
        expect(issues, hasLength(1));
      } finally {
        await provider.close();
      }
    },
  );

  test('panning beyond the key budget retires old cached images', () async {
    final file = await rasterFixture(root);
    final archive = await RasterArchive.open(
      file.path,
      factory: databaseFactoryFfi,
    );
    final provider = RasterTileProvider(
      archive,
      onIssue: (error) => fail('$error'),
    );
    try {
      final layer = TileLayer(tileProvider: provider);
      final first = provider.getImage(const TileCoordinates(0, 0, 10), layer);
      final key = await first.obtainKey(ImageConfiguration.empty);
      await imageSize(first);
      expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
      for (var i = 1; i <= RasterLimits.cacheKeys; i++) {
        await imageSize(provider.getImage(TileCoordinates(i, 0, 10), layer));
      }
      expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
    } finally {
      await provider.close();
    }
  });
}
