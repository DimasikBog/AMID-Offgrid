import 'package:amid_offgrid/models/appearance.dart';
import 'package:amid_offgrid/screens/appearance_screen.dart';
import 'package:amid_offgrid/widgets/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ten palettes are distinct and preference roundtrips reject unknown values atomically', () async {
    expect(appearancePresets, hasLength(10));
    expect(
      appearancePresets
          .map(
            (p) =>
                offgridTheme(Brightness.dark, style: p.id).colorScheme.primary,
          )
          .toSet(),
      hasLength(10),
    );
    final a = await openTestStore(), b = await openTestStore();
    try {
      await a.store.setThemeStyle('cyberpunk');
      await b.store.restore(a.store.backup());
      expect(b.store.themeStyle, 'cyberpunk');
      final before = b.store.snapshot();
      await expectLater(
        b.store.restore({...a.store.backup(), 'themeStyle': 'script'}),
        throwsFormatException,
      );
      expect(b.store.snapshot(), before);
      await a.store.setThemeStyle('classic');
      await b.store.applyPersonalization(a.store.personalization);
      expect(b.store.themeStyle, 'classic');
    } finally {
      await a.store.close();
      await b.store.close();
      await a.root.delete(recursive: true);
      await b.root.delete(recursive: true);
    }
  });
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets('styles remain usable at width $width with large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = (await tester.runAsync(openTestStore))!;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: offgridTheme(Brightness.dark, style: 'cyberpunk'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: AppearanceScreen(store: f.store),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('appearance-cyberpunk')),
          250,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('appearance-cyberpunk')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(f.store.themeStyle, 'cyberpunk');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await f.store.close();
          await f.root.delete(recursive: true);
        });
      }
    });
  }
}
