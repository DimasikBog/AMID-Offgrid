import 'package:amid_offgrid/screens/map_screen.dart';
import 'package:amid_offgrid/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'short large-text map keeps controls reachable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 280);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = (await tester.runAsync(openTestStore))!;
      await tester.runAsync(() => fixture.store.setStreetMode('overview'));
      final services = Services(fixture.store);
      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('uk'),
            supportedLocales: const [Locale('uk')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: MapScreen(services: services, navigate: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.widget<Scrollbar>(find.byType(Scrollbar)).interactive,
          isTrue,
        );
        await tester.ensureVisible(find.byTooltip('До області карти'));
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('До області карти').hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('До області карти'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        services.dispose();
        await tester.runAsync(() async {
          await fixture.store.close();
          await fixture.root.delete(recursive: true);
        });
      }
    },
  );
}
