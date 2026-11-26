import 'package:amid_offgrid/main.dart';
import 'package:amid_offgrid/models/street_map.dart';
import 'package:amid_offgrid/screens/preparation_screen.dart';
import 'package:amid_offgrid/screens/emergency_screen.dart';
import 'package:amid_offgrid/services/services.dart';
import 'package:amid_offgrid/widgets/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'preparation at 320px/$scale updates inventory and opens only training SOS',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = (await tester.runAsync(openTestStore))!;
        final services = Services(f.store);
        var openedMap = 0, openedPacks = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: offgridTheme(Brightness.dark, style: 'cyberpunk'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: PreparationScreen(
              services: services,
              openPacks: () => openedPacks++,
              openMap: () => openedMap++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Детальні вулиці ще не збережені'),
          180,
        );
        await tester.pumpAndSettle();
        expect(find.text('Детальні вулиці ще не збережені'), findsOneWidget);
        // An atlas or overview must never count as a detailed street region.
        await tester.runAsync(
          () => f.store.addAsset({
            'id': 'fixture-atlas',
            'kind': 'atlas',
            'title': 'Atlas',
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text('Детальні вулиці ще не збережені'), findsOneWidget);
        final bounds = StreetBounds(15.1, 50.0, 15.1001, 50.0001);
        final tiles = bounds.tiles(10);
        await tester.runAsync(
          () => f.store.saveStreetRegion({
            'id': '11111111-1111-1111-1111-111111111111',
            'title': 'Fixture region',
            'source': streetArchiveUrl,
            'bounds': bounds.json,
            'maxZoom': 10,
            'createdAt': '2026-11-26T00:00:00Z',
            'bytes': tiles.length,
            'tiles': {
              for (final tile in tiles)
                tile.key: {'bytes': 1, 'sha256': 'a' * 64},
            },
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text('Областей з вулицями: 1'), findsOneWidget);
        expect(find.text('Детальні вулиці ще не збережені'), findsNothing);
        Future<void> tap(String text) async {
          await tester.scrollUntilVisible(find.text(text), 180);
          await tester.ensureVisible(find.text(text));
          await tester.pumpAndSettle();
          await tester.tap(find.text(text));
          await tester.pumpAndSettle();
        }

        await tap('Відкрити карту');
        expect(openedMap, 1);
        await tester.runAsync(
          () => f.store.addAsset({
            'id': 'fixture-map',
            'kind': 'map',
            'title': 'Fixture map',
            'bytes': 1,
            'path': 'unopened-fixture.mbtiles',
          }),
        );
        await tester.pumpAndSettle();
        final regionButton = find.byKey(
          const ValueKey(
            'prepared-region-11111111-1111-1111-1111-111111111111',
          ),
        );
        await tester.ensureVisible(regionButton);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(regionButton);
          await tester.tap(regionButton);
          final deadline = DateTime.now().add(const Duration(seconds: 3));
          while (openedMap < 2 && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(services.streets.error, isNull);
        expect(services.streets.mode, '11111111-1111-1111-1111-111111111111');
        expect(openedMap, 2);
        expect(f.store.selectedMap, isEmpty);
        expect(f.store.streetMode, services.streets.mode);
        await tap('Офлайн-набір і резервна копія');
        expect(openedPacks, 1);
        await tap('Відкрити тренування SOS');
        expect(
          tester
              .widget<EmergencyScreen>(find.byType(EmergencyScreen))
              .initialTraining,
          isTrue,
        );
        expect(find.text('Тренування · SOS · Виклик 112'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        services.dispose();
        await tester.runAsync(() async {
          await f.store.close();
          await f.root.delete(recursive: true);
        });
      },
    );
  }
  testWidgets('quick actions open preparation from the real app shell', (
    tester,
  ) async {
    final f = (await tester.runAsync(openTestStore))!;
    await tester.pumpWidget(
      MaterialApp(
        home: OffgridShell(store: f.store, themeAction: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Швидкі дії'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Перед дорогою'));
    await tester.pumpAndSettle();
    expect(find.byType(PreparationScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await f.store.close();
      await f.root.delete(recursive: true);
    });
  });
}
