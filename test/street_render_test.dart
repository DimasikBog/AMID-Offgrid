import 'dart:io';

// Renderer test hook: Flutter tests otherwise replace labels with Ahem boxes.
import 'package:flutter_map_vector_tiles/src/render/label_painter.dart'
    show LabelPainter;

import 'package:amid_offgrid/widgets/app_theme.dart';
import 'package:amid_offgrid/widgets/street_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    LabelPainter.debugFontFamilies = ['Roboto'];
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto.ttf'))).load();
  });
  tearDownAll(() {
    LabelPainter.debugFontFamilies = null;
  });
  for (final style in ['classic', 'cyberpunk']) {
    testWidgets(
      'real offline streets, buildings and road names render in $style',
      (tester) async {
        tester.view.physicalSize = const Size(500, 500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = vt.VectorTileLayerController();
        final provider = vt.MemoryVectorTileProvider(
          tiles: {
            for (var x = 17758; x <= 17760; x++)
              vt.TileKey(15, x, 11104): File(
                'test/fixtures/streets/15-$x-11104.pbf',
              ).readAsBytesSync(),
          },
          maximumZoom: 15,
        );
        final theme = offgridTheme(
          style == 'classic' ? Brightness.light : Brightness.dark,
          style: style,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: const ValueKey('map'),
              child: Scaffold(
                body: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(50.060665, 15.111694),
                    initialZoom: 17,
                  ),
                  children: [
                    vt.VectorTileLayer(
                      theme: streetTheme(theme.colorScheme, style),
                      tileProviders: vt.TileProviders({'streets': provider}),
                      controller: controller,
                      retainAllProperties: true,
                      concurrency: 1,
                      tileFadeDuration: Duration.zero,
                      labelFadeDuration: Duration.zero,
                      diskCacheMaximumSizeInBytes: 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        Set<String> layers = {};
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          layers = controller
              .queryRenderedFeaturesInRect(const Rect.fromLTWH(0, 0, 500, 500))
              .map((f) => f.layerId)
              .toSet();
          if (layers.contains('road-names') && layers.contains('buildings')) {
            break;
          }
        }
        await tester.pump(const Duration(milliseconds: 500));
        expect(layers, contains('roads'));
        expect(layers, contains('buildings'));
        expect(layers, contains('road-names'));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('map')),
          matchesGoldenFile('goldens/streets_$style.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      },
    );
  }
}
