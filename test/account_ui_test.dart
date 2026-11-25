import 'package:amid_offgrid/screens/account_screen.dart';
import 'package:amid_offgrid/screens/catalog_screen.dart';
import 'package:amid_offgrid/services/account_service.dart';
import 'package:amid_offgrid/services/services.dart';
import 'package:amid_offgrid/widgets/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'Roboto': 'assets/fonts/Roboto.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  test(
    'account credential bounds match Unicode and obvious-repeat constraints',
    () {
      expect(validAccountUsername('amid_123'), isTrue);
      expect(validAccountUsername('../admin'), isFalse);
      expect(validAccountPassword('a long unique phrase'), isTrue);
      expect(validAccountPassword(' ' * 20), isFalse);
      expect(validAccountPassword('short'), isFalse);
      expect(validAccountPassword('💚' * 19), isFalse);
    },
  );
  for (final width in [390.0, 320.0]) {
    testWidgets(
      'account and catalogue remain usable at width $width with large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 680);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = (await tester.runAsync(openTestStore))!;
        final services = (await tester.runAsync(() async {
          final services = Services(f.store);
          await services.catalog.entries;
          return services;
        }))!;
        Widget wrap(Widget screen) => MaterialApp(
          theme: offgridTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(width == 320 ? 2 : 1)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('catalog-design'),
            child: screen,
          ),
        );
        await tester.pumpWidget(wrap(AccountScreen(account: services.account)));
        await tester.pumpAndSettle();
        expect(find.text('Твій акаунт AMID'), findsOneWidget);
        if (width == 390) {
          await expectLater(
            find.byKey(const ValueKey('catalog-design')),
            matchesGoldenFile('goldens/account_phone.png'),
          );
        }
        await tester.drag(find.byType(ListView), const Offset(0, -700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await tester.pumpWidget(wrap(CatalogScreen(services: services)));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.text('Твоя бібліотека можливостей'), findsOneWidget);
        if (width == 390) {
          await expectLater(
            find.byKey(const ValueKey('catalog-design')),
            matchesGoldenFile('goldens/catalog_phone.png'),
          );
        }
        for (var i = 0; i < 4; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -650));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          services.dispose();
          await f.store.close();
          await f.root.delete(recursive: true);
        });
      },
    );
  }
}
