import 'dart:io';

import 'package:amid_offgrid/main.dart' as app;
import 'package:amid_offgrid/screens/lite_screen.dart';
import 'package:amid_offgrid/screens/messages_screen.dart';
import 'package:amid_offgrid/screens/assistant_screen.dart';
import 'package:amid_offgrid/models/starter_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:integration_test/integration_test.dart';

Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 200),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 45),
);

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native navigation, note, favorite, Lite and reopened SQLite', (
    tester,
  ) async {
    const title = 'AMID перевірка емулятора';
    const body = 'Тільки синтетичні дані для перевірки збереження на пристрої.';
    await app.main(const []);
    await settle(tester);
    expect(find.byType(app.OffgridShell), findsOneWidget);
    final store = tester
        .widget<app.OffgridShell>(find.byType(app.OffgridShell))
        .store;
    expect(store.articles, isNotEmpty);
    final catalog = await StarterCatalog.load(rootBundle);
    final full = await BundledModel.load(rootBundle, catalog.model) != null;
    if (full) {
      for (
        var i = 0;
        i < 1800 && !store.packs.any((p) => p['id'] == starterModelId);
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await store.flush();
      final model = store.packs.singleWhere((p) => p['id'] == starterModelId);
      expect(model['sha256'], catalog.model.sha256);
      expect(await File(model['path'] as String).length(), catalog.model.bytes);
      debugPrint(
        'AMID_STARTER_INSTALLED ${Platform.operatingSystem}: ${catalog.model.bytes} verified bytes, no network',
      );
      await settle(tester);
    }
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('01-home');

    await tester.tap(find.text('Знання').last);
    await settle(tester);
    await tester.tap(find.byTooltip('Створити нотатку'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).at(0), title);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    final formScroll = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    final bodyField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Текст',
    );
    // On iPhone SE the real keyboard can unmount lazy fields below the fold.
    await tester.scrollUntilVisible(bodyField, 220, scrollable: formScroll);
    await tester.enterText(bodyField, body);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Зберегти на пристрої'),
      220,
      scrollable: formScroll,
    );
    await tester.tap(find.text('Зберегти на пристрої'));
    await settle(tester);
    await store.flush();
    await tester.enterText(find.byType(TextField).first, title);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.tap(find.byTooltip('Знайти'));
    final tile = find.widgetWithText(ListTile, title);
    // A query's EditableText is not evidence that its async result has loaded.
    await waitFor(tester, tile);
    await tester.ensureVisible(tile);
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(IconButton)),
    );
    await settle(tester);
    await store.flush();
    final note = store.articles.singleWhere((item) => item.title == title);
    expect(store.favoriteKeys, contains(note.key));
    await binding.takeScreenshot('02-note-favorite');

    await tester.tap(find.text('Помічник').last);
    await settle(tester);
    expect(find.text('Твій помічник'), findsOneWidget);
    if (full) {
      final ai = tester
          .widget<AssistantScreen>(find.byType(AssistantScreen))
          .services
          .assistant;
      await tester.enterText(
        find.byType(TextField).first,
        'Reply with the word OK only.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      await tester.ensureVisible(find.text('Запитати модель'));
      await tester.tap(find.text('Запитати модель'));
      for (var i = 0; i < 1800 && (ai.busy || !ai.generated); i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (ai.error != null) break;
      }
      expect(ai.error, isNull);
      expect(ai.generated, true);
      expect(ai.answer.trim(), isNotEmpty);
      expect(ai.ready, true);
      debugPrint(
        'AMID_MOBILE_AI_PASS ${Platform.operatingSystem}: first-question autoload and local inference, ${ai.answer.length} characters',
      );
      await ai.unload();
    }
    await tester.tap(find.text('Карта').last);
    await settle(tester);
    expect(find.text('Оглядова карта світу · без вулиць'), findsOneWidget);
    // An idle frame may precede the asynchronous bundled GeoJSON load.
    await waitFor(
      tester,
      find.byWidgetPredicate(
        (widget) => widget is PolygonLayer && widget.polygons.isNotEmpty,
      ),
    );
    await settle(tester);
    await binding.takeScreenshot('03-map');
    await tester.tap(find.text('Зв’язок').last);
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Нове повідомлення'),
      220,
      scrollable: find
          .descendant(
            of: find.byType(MessagesScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Нове повідомлення'), findsOneWidget);
    await tester.tap(find.byTooltip('Швидкі дії'));
    await settle(tester);
    await tester.tap(find.text('Легкий режим'));
    await settle(tester);
    expect(find.byType(LiteScreen), findsOneWidget);
    final checkbox = find.byType(CheckboxListTile).first;
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await settle(tester);
    await store.flush();
    expect(store.preparation, contains('water'));
    await binding.takeScreenshot('04-lite');
    expect(tester.takeException(), isNull);

    // Recreate the real app and reopen the platform SQLite database, no mocks.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await store.close();
    await app.main(const []);
    await settle(tester);
    final reopened = tester
        .widget<app.OffgridShell>(find.byType(app.OffgridShell))
        .store;
    final restored = reopened.articles.singleWhere(
      (item) => item.title == title,
    );
    expect(restored.body, body);
    expect(reopened.favoriteKeys, contains(restored.key));
    expect(reopened.preparation, contains('water'));
    expect(
      (await reopened.search(title)).map((item) => item.key),
      contains(restored.key),
    );
    expect(
      (await reopened.search('перевір')).map((item) => item.key),
      contains(restored.key),
    );
    await binding.takeScreenshot('05-reopened');
    expect(tester.takeException(), isNull);
    debugPrint(
      'AMID_MOBILE_EMULATOR_PASS ${Platform.operatingSystem}: navigation, note, favorite, Lite, SQLite reopen',
    );
  });
}
