import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:amid_offgrid/main.dart';
import 'package:amid_offgrid/services/backend_native.dart';
import 'package:amid_offgrid/services/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    '390px native navigation, library, search-only assistant, map and drafts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pair = await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('amid-widget-');
        final store = await AppStore.open(
          backend: await PlatformBackend.open(
            factory: databaseFactoryFfi,
            root: root,
          ),
          seedText: File('assets/starter.json').readAsStringSync(),
        );
        await store.setStreetMode('overview');
        return (root, store);
      });
      final root = pair!.$1, store = pair.$2;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('uk'),
          supportedLocales: const [Locale('uk')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(useMaterial3: true),
          home: OffgridShell(store: store, themeAction: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Твій світ.\nБез мережі.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Знання'));
      await tester.pumpAndSettle();
      expect(find.text('Пошук у твоїх матеріалах'), findsOneWidget);
      await tester.tap(find.text('Помічник').last);
      await tester.pumpAndSettle();
      expect(find.text('Пошук у матеріалах'), findsOneWidget);
      await tester.tap(find.text('Карта').last);
      await tester.pumpAndSettle();
      expect(find.text('Оглядова карта світу · без вулиць'), findsOneWidget);
      await tester.tap(find.text('Зв’язок').last);
      await tester.pumpAndSettle();
      expect(find.text('Нове повідомлення'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}
