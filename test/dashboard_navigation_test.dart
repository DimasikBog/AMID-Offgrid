import 'package:amid_offgrid/main.dart';
import 'package:amid_offgrid/widgets/app_theme.dart';
import 'package:amid_offgrid/widgets/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets(
    'home search focuses input; favorite shortcut resets stale filters on repeat',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = (await tester.runAsync(openTestStore))!;
      final article = f.store.articles.first;
      await tester.runAsync(() => f.store.toggleFavorite(article.key));
      await tester.pumpWidget(
        MaterialApp(
          theme: offgridTheme(Brightness.light),
          home: OffgridShell(store: f.store, themeAction: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DashboardSearch));
      await tester.tap(find.byType(DashboardSearch));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .focusNode
            ?.hasFocus,
        isTrue,
      );
      await tester.enterText(
        find.byType(TextField).first,
        'немає-такої-статті',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Головна'));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.ensureVisible(find.byType(CollectionSummary));
        await tester.pumpAndSettle();
        await tester.tap(find.text('в обраному'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilterChip>(find.byType(FilterChip)).selected,
          isTrue,
        );
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller
              ?.text,
          isEmpty,
        );
        expect(find.text(article.title), findsOneWidget);
        await tester.tap(find.text('Обране'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilterChip>(find.byType(FilterChip)).selected,
          isFalse,
        );
        await tester.tap(find.text('Головна'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        await f.store.close();
        await f.root.delete(recursive: true);
      });
    },
  );
}
