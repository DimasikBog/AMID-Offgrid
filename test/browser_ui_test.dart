import 'package:amid_offgrid/models/web_page.dart';
import 'package:amid_offgrid/screens/browser_screen.dart';
import 'package:amid_offgrid/services/web_reader.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support.dart';

class _FixtureReader extends WebReader {
  @override
  Future<ReaderPage> fetch(String address) async => ReaderPage.fromHtml(
    '<title>Довідка AMID</title><article><h1>Карти із собою</h1><p>УнікальнийВебМатеріал для офлайн-читання.</p><a href="/next">Далі</a></article>',
    checkedWebUri(address),
    receivedBytes: 200,
  );
}

void main() {
  testWidgets(
    'address entry, reading and explicit offline save share the real store',
    (tester) async {
      final f = (await tester.runAsync(openTestStore))!;
      final reader = _FixtureReader();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: BrowserScreen(store: f.store, reader: reader),
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('browser-address')),
          'https://example.org/guide',
        );
        await tester.tap(find.byTooltip('Відкрити адресу'));
        await tester.pumpAndSettle();
        expect(
          find.text('Довідка AMID'),
          findsOneWidget,
          reason: tester.allWidgets
              .whereType<Text>()
              .map((w) => w.data)
              .join('\n'),
        );
        expect(find.textContaining('УнікальнийВебМатеріал'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Зберегти офлайн'));
          await f.store.flush();
        });
        await tester.pumpAndSettle();
        expect(
          f.store.articles.where((a) => a.packId == AppStore.webPagesId),
          hasLength(1),
        );
        expect(
          (await tester.runAsync(
            () => f.store.search('УнікальнийВебМатеріал'),
          ))!.single.title,
          'Довідка AMID',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await f.store.close();
          await f.root.delete(recursive: true);
        });
      }
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'offline page opens without any network at reader scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = (await tester.runAsync(openTestStore))!;
        var requests = 0;
        final reader = WebReader(
          clientFactory: () => MockClient((_) async {
            requests++;
            return http.Response('Unexpected', 500);
          }),
        );
        await tester.runAsync(
          () => f.store.saveWebPage(
            ReaderPage.fromPlainText(
              'Текст без мережі',
              Uri.parse('https://example.org/offline'),
              receivedBytes: 20,
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: BrowserScreen(store: f.store, reader: reader),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Збережені сторінки'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('example.org'));
        await tester.pumpAndSettle();
        expect(find.text('Збережено на пристрої'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.textContaining('Текст без мережі'),
          150,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.textContaining('Текст без мережі'), findsOneWidget);
        expect(requests, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await f.store.close();
          await f.root.delete(recursive: true);
        });
      },
    );
  }
}
