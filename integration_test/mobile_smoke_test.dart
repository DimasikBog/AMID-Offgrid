import 'dart:io';

import 'package:amid_offgrid/main.dart' as app;
import 'package:amid_offgrid/screens/lite_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 200),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 45),
);

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
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('01-home');

    await tester.tap(find.text('Знання').last);
    await settle(tester);
    await tester.tap(find.byTooltip('Створити нотатку'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).at(0), title);
    await tester.enterText(find.byType(TextFormField).at(2), body);
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Зберегти на пристрої'));
    await tester.tap(find.text('Зберегти на пристрої'));
    await settle(tester);
    await store.flush();
    await tester.enterText(find.byType(TextField).first, title);
    tester.testTextInput.hide();
    await settle(tester);
    expect(find.text(title), findsOneWidget);
    final tile = find.ancestor(
      of: find.text(title),
      matching: find.byType(ListTile),
    );
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
    expect(find.text('Пошук у матеріалах'), findsOneWidget);
    await tester.tap(find.text('Карта').last);
    await settle(tester);
    expect(find.text('Оглядова карта світу · без вулиць'), findsOneWidget);
    await binding.takeScreenshot('03-map');
    await tester.tap(find.text('Зв’язок').last);
    await settle(tester);
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
    await binding.takeScreenshot('05-reopened');
    expect(tester.takeException(), isNull);
    debugPrint(
      'AMID_MOBILE_EMULATOR_PASS ${Platform.operatingSystem}: navigation, note, favorite, Lite, SQLite reopen',
    );
  });
}
