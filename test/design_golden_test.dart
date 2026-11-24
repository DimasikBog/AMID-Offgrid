import 'package:amid_offgrid/main.dart';
import 'package:amid_offgrid/widgets/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
  for (final layout in [
    (
      name: 'phone',
      size: const Size(390, 844),
      brightness: Brightness.light,
      scale: 1.0,
    ),
    (
      name: 'desktop',
      size: const Size(1440, 900),
      brightness: Brightness.dark,
      scale: 1.0,
    ),
    (
      name: 'large_text',
      size: const Size(320, 480),
      brightness: Brightness.light,
      scale: 2.0,
    ),
  ]) {
    testWidgets('reviewed home layout ${layout.name}', (tester) async {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = (await tester.runAsync(openTestStore))!;
      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('uk'),
            supportedLocales: const [Locale('uk')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: offgridTheme(layout.brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(layout.scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: const ValueKey('design'),
              child: OffgridShell(store: f.store, themeAction: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('design')),
          matchesGoldenFile('goldens/home_${layout.name}.png'),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await f.store.close();
          await f.root.delete(recursive: true);
        });
      }
    });
  }
}
