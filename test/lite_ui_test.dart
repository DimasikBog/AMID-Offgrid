import 'package:amid_offgrid/screens/lite_screen.dart';
import 'package:amid_offgrid/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets(
    'light reader has no AI actions and preserves scale and checklist changes',
    (tester) async {
      final f = (await tester.runAsync(openTestStore))!;
      await tester.runAsync(() async {
        await f.store.saveNote(
          title: 'Під рукою',
          body: 'Особиста синтетична нотатка',
        );
        await f.store.toggleFavorite(f.store.articles.last.key);
      });
      final services = Services(f.store);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      try {
        await tester.pumpWidget(
          MaterialApp(home: LiteScreen(services: services)),
        );
        await tester.pumpAndSettle();
        final checkbox = find.byType(CheckboxListTile).first;
        await tester.ensureVisible(checkbox);
        await tester.runAsync(() async {
          await tester.tap(checkbox);
          await f.store.flush();
        });
        await tester.pump();
        expect(f.store.preparation, {'water'});
        final note = find.text('Під рукою');
        await tester.ensureVisible(note);
        await tester.tap(note);
        await tester.pumpAndSettle();
        expect(find.text('Запитати про статтю'), findsNothing);
        expect(find.text('Додати до повідомлення'), findsNothing);
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('Більший шрифт'));
          await f.store.flush();
        });
        await tester.pump();
        expect(f.store.readerScale, closeTo(1.1, 1e-9));
        await tester.tap(find.byTooltip('Скопіювати текст'));
        await tester.pump();
        expect(copied, contains('Особиста синтетична нотатка'));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        services.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        await tester.runAsync(() async {
          await f.store.close();
          await f.root.delete(recursive: true);
        });
      }
    },
  );
}
