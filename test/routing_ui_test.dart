import 'dart:async';
import 'dart:io';

import 'package:amid_offgrid/models/data.dart';
import 'package:amid_offgrid/models/route_network.dart';
import 'package:amid_offgrid/screens/route_planner.dart';
import 'package:amid_offgrid/screens/map_screen.dart';
import 'package:amid_offgrid/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Json pack() => parsePack(
    decodeObject(File('examples/route_network.json').readAsStringSync()),
  );

  Widget app(Widget screen) => MaterialApp(
    locale: const Locale('uk'),
    supportedLocales: const [Locale('uk')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: screen,
  );

  Future<void> endpoints(WidgetTester tester) async {
    await tester.tap(find.text('Початок'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'пункт A');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Навчальний пункт A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Кінець'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Навчальний пункт C'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'real background route returns to the map and disappears with its source',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = (await tester.runAsync(openTestStore))!;
      final source = pack();
      // A tall route exposes fitting against the old, larger map viewport.
      source['routing']['nodes'][2]['coordinate'] = [.0001, .004];
      await tester.runAsync(() => fixture.store.importKnowledge(source));
      await tester.runAsync(() => fixture.store.setStreetMode('overview'));
      final services = Services(fixture.store);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ListenableBuilder(
              listenable: fixture.store,
              builder: (_, _) =>
                  MapScreen(services: services, navigate: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Побудувати маршрут'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Офлайн з мережі маршруту'));
      await tester.pumpAndSettle();
      await endpoints(tester);
      await tester.ensureVisible(find.text('Побудувати маршрут'));
      await tester.tap(find.text('Побудувати маршрут'));
      for (var i = 0; i < 500; i++) {
        await tester.pump();
        if (find.text('Показати на карті').evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(find.text('Показати на карті'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Показати на карті').hitTestable(),
        100,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Показати на карті'));
      await tester.pumpAndSettle();
      expect(find.text('До маршруту'), findsOneWidget);
      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .last
            .points,
        hasLength(3),
      );
      expect(tester.takeException(), isNull);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final points = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .last
          .points;
      expect(
        points.every(map.mapController!.camera.visibleBounds.contains),
        isTrue,
      );
      await tester.runAsync(
        () => fixture.store.removePack(source['id'] as String),
      );
      await tester.pumpAndSettle();
      expect(find.text('До маршруту'), findsNothing);
      expect(find.byTooltip('Прибрати маршрут'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      services.dispose();
      await tester.runAsync(() async {
        await fixture.store.close();
        await fixture.root.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'search endpoints, calculate offline and reverse a one-way route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = (await tester.runAsync(openTestStore))!;
      await tester.runAsync(() => fixture.store.importKnowledge(pack()));
      await tester.runAsync(() => fixture.store.setStreetMode('overview'));
      final services = Services(fixture.store);
      await tester.pumpWidget(
        app(
          RoutePlannerScreen(
            services: services,
            calculate: (input) async => calculateOfflineRoute(input),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await endpoints(tester);
      final build = find.widgetWithText(FilledButton, 'Побудувати маршрут');
      await tester.ensureVisible(build);
      await tester.tap(build);
      await tester.pumpAndSettle();
      expect(find.text('222 м'), findsOneWidget);
      expect(find.text('Показати на карті'), findsOneWidget);
      expect(
        find.text('2 ділянок · Навчальний пункт A → Навчальний пункт C'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Поміняти напрямок'));
      await tester.tap(find.text('Поміняти напрямок'));
      await tester.pumpAndSettle();
      expect(find.text('Показати на карті'), findsNothing);
      await tester.tap(build);
      await tester.pumpAndSettle();
      expect(
        find.text('1 ділянок · Навчальний пункт C → Навчальний пункт A'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      services.dispose();
      await tester.runAsync(() async {
        await fixture.store.close();
        await fixture.root.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'cancelled results and removed source networks cannot publish a route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = (await tester.runAsync(openTestStore))!;
      final networkPack = pack();
      await tester.runAsync(() => fixture.store.importKnowledge(networkPack));
      await tester.runAsync(() => fixture.store.setStreetMode('overview'));
      final services = Services(fixture.store);
      final first = Completer<OfflineRoute>(),
          second = Completer<OfflineRoute>();
      var requests = 0;
      await tester.pumpWidget(
        app(
          RoutePlannerScreen(
            services: services,
            calculate: (_) => requests++ == 0 ? first.future : second.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await endpoints(tester);
      final build = find.text('Побудувати маршрут');
      await tester.ensureVisible(build);
      await tester.tap(build);
      await tester.pump();
      await tester.ensureVisible(find.text('Скасувати обчислення'));
      await tester.tap(find.text('Скасувати обчислення'));
      await tester.pumpAndSettle();
      final route = RouteNetwork.parse(networkPack['routing'])
          .shortestPath('a', 'c');
      first.complete(route);
      await tester.pumpAndSettle();
      expect(find.text('Показати на карті'), findsNothing);
      await tester.tap(build);
      await tester.pump();
      await tester.runAsync(
        () => fixture.store.removePack(networkPack['id'] as String),
      );
      await tester.pumpAndSettle();
      second.complete(route);
      await tester.pumpAndSettle();
      expect(find.text('Маршрутних мереж поки немає.'), findsOneWidget);
      expect(find.text('Показати на карті'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      services.dispose();
      await tester.runAsync(() async {
        await fixture.store.close();
        await fixture.root.delete(recursive: true);
      });
    },
  );

  testWidgets('backgrounding invalidates a pending calculation before resume', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = (await tester.runAsync(openTestStore))!;
    final source = pack();
    await tester.runAsync(() => fixture.store.importKnowledge(source));
    final services = Services(fixture.store),
        pending = Completer<OfflineRoute>();
    await tester.pumpWidget(
      app(
        RoutePlannerScreen(
          services: services,
          calculate: (_) => pending.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await endpoints(tester);
    await tester.ensureVisible(find.text('Побудувати маршрут'));
    await tester.tap(find.text('Побудувати маршрут'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    pending.complete(
      RouteNetwork.parse(source['routing']).shortestPath('a', 'c'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Показати на карті'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    services.dispose();
    await tester.runAsync(() async {
      await fixture.store.close();
      await fixture.root.delete(recursive: true);
    });
  });

  testWidgets('320px large-text planner handles an empty network library', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = (await tester.runAsync(openTestStore))!;
    await tester.runAsync(() => fixture.store.setStreetMode('overview'));
    final services = Services(fixture.store);
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.6),
          ),
          child: RoutePlannerScreen(services: services),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Маршрутних мереж поки немає.'),
      150,
    );
    expect(find.text('Маршрутних мереж поки немає.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Додати пакет мережі'), 150);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    services.dispose();
    await tester.runAsync(() async {
      await fixture.store.close();
      await fixture.root.delete(recursive: true);
    });
  });
}
