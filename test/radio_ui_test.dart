import 'package:amid_offgrid/screens/radio_dock_screen.dart';
import 'package:amid_offgrid/services/radio_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'radio_support.dart';
import 'support.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'radio control stays usable on a small screen, including keyboard at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final f = (await tester.runAsync(openTestStore))!;
        final transport = FixtureRadio();
        final radio = (await tester.runAsync(
          () async => RadioDockService(f.store, transport),
        ))!;
        try {
          await tester.runAsync(() => radio.connect('one'));
          radio.chooseChannel(1);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RadioDockScreen(service: radio, store: f.store),
            ),
          );
          await tester.pumpAndSettle();
          final scroll = find.byType(Scrollable).first;
          final antenna = find.widgetWithText(
            CheckboxListTile,
            'Антена підключена й розкладена',
          );
          final checkbox = find.descendant(
            of: antenna,
            matching: find.byType(Checkbox),
          );
          await tester.scrollUntilVisible(checkbox, 200, scrollable: scroll);
          await tester.pumpAndSettle();
          await tester.tap(checkbox);
          await tester.pumpAndSettle();
          final destination = find.byKey(const ValueKey('radio-destination'));
          await tester.scrollUntilVisible(destination, 100, scrollable: scroll);
          await tester.pumpAndSettle();
          await tester.enterText(destination, '!1234abcd');
          final message = find.byKey(const ValueKey('radio-message'));
          await tester.scrollUntilVisible(message, 150, scrollable: scroll);
          await tester.pumpAndSettle();
          await tester.enterText(message, 'Короткий тест');
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
          final send = find.widgetWithText(
            FilledButton,
            'Надіслати через LoRa',
          );
          await tester.scrollUntilVisible(send, 150, scrollable: scroll);
          await tester.pumpAndSettle();
          expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
          await tester.runAsync(() async {
            await tester.tap(send);
            await f.store.flush();
          });
          await tester.pumpAndSettle();
          expect(radio.transmissions.single.text, 'Короткий тест');
          expect(radio.transmissions.single.state, RadioDelivery.bluetooth);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          radio.dispose();
          await tester.runAsync(() async {
            await f.store.close();
            await f.root.delete(recursive: true);
          });
        }
      },
    );
  }
}
