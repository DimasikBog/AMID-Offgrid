import 'package:amid_offgrid/main.dart';
import 'package:amid_offgrid/screens/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(1440, 900),
    const Size(320, 480),
  ]) {
    testWidgets('adaptive shell, lazy tabs and search shortcut at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = (await tester.runAsync(openTestStore))!;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('uk'),
          supportedLocales: const [Locale('uk')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(size.width == 320 ? 2 : 1),
            ),
            child: child!,
          ),
          home: OffgridShell(store: f.store, themeAction: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'home at $size');
      expect(find.byType(MapScreen, skipOffstage: false), findsNothing);
      expect(
        find.byType(NavigationRail),
        size.width >= 840 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(NavigationBar),
        size.width < 840 ? findsOneWidget : findsNothing,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(find.byType(TextField).first);
      expect(input.focusNode?.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        await f.store.close();
        await f.root.delete(recursive: true);
      });
    });
  }
}
