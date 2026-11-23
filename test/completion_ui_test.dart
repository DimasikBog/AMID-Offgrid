import 'package:amid_offgrid/models/data.dart';
import 'package:amid_offgrid/screens/basic.dart';
import 'package:amid_offgrid/screens/messages_screen.dart';
import 'package:amid_offgrid/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Widget app(Widget body) => MaterialApp(
    locale: const Locale('uk'),
    supportedLocales: const [Locale('uk')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: body),
  );

  testWidgets('create note and favorite it through the library', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = (await tester.runAsync(openTestStore))!;
    final services = Services(fixture.store);
    await tester.pumpWidget(
      app(
        ListenableBuilder(
          listenable: fixture.store,
          builder: (_, _) =>
              LibraryScreen(services: services, navigate: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Створити нотатку'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Запас води');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'Зберегти двадцять літрів',
    );
    await tester.ensureVisible(find.text('Зберегти на пристрої'));
    await tester.tap(find.text('Зберегти на пристрої'));
    await tester.runAsync(fixture.store.flush);
    await tester.pumpAndSettle();
    expect(find.text('Запас води'), findsOneWidget);
    final tile = find.ancestor(
      of: find.text('Запас води'),
      matching: find.byType(ListTile),
    );
    await tester.ensureVisible(tile);
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(IconButton)),
    );
    await tester.runAsync(fixture.store.flush);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Обране'));
    await tester.pumpAndSettle();
    expect(find.text('Запас води'), findsOneWidget);
    expect(fixture.store.favoriteKeys, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    services.dispose();
    await tester.runAsync(() async {
      await fixture.store.close();
      await fixture.root.delete(recursive: true);
    });
  });

  testWidgets('an unrelated store notification preserves an unsaved draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = (await tester.runAsync(openTestStore))!;
    final services = Services(fixture.store);
    await tester.pumpWidget(app(MessagesScreen(services: services)));
    await tester.pumpAndSettle();
    final input = find.byType(TextField).first;
    await tester.ensureVisible(input);
    await tester.enterText(input, 'Не губи цей текст');
    await tester.runAsync(
      () => fixture.store.savePin(const Pin('pin', 'Дім', 48, 22)),
    );
    await tester.pump();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Не губи цей текст',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(fixture.store.flush);
    expect(fixture.store.draft, 'Не губи цей текст');
    services.dispose();
    await tester.runAsync(() async {
      await fixture.store.close();
      await fixture.root.delete(recursive: true);
    });
  });
}
