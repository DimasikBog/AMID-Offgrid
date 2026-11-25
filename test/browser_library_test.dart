import 'dart:async';

import 'package:amid_offgrid/models/web_page.dart';
import 'package:amid_offgrid/screens/browser_screen.dart';
import 'package:amid_offgrid/screens/saved_pages_screen.dart';
import 'package:amid_offgrid/services/web_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

ReaderPage _page(
  String path, {
  String? link,
  String text = 'Матеріал',
}) => ReaderPage.fromHtml(
  '<title>$path</title><article><p>$text</p>${link == null ? '' : '<a href="/$link">Перейти до $link</a>'}</article>',
  Uri.parse('https://example.org/$path'),
  receivedBytes: 100,
);

class _Reader extends WebReader {
  final requests = <String>[];
  Completer<ReaderPage>? pending;
  @override
  Future<ReaderPage> fetch(String address) {
    requests.add(address);
    return pending?.future ??
        Future.value(_page(Uri.parse(address).path.substring(1)));
  }
}

Future<void> _go(WidgetTester tester, String address) async {
  await tester.enterText(
    find.byKey(const ValueKey('browser-address')),
    address,
  );
  await tester.tap(find.byTooltip('Відкрити адресу'));
  await tester.pumpAndSettle();
}

Future<void> _link(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.widgetWithText(ListTile, title),
    250,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.widgetWithText(ListTile, title));
  await tester.pumpAndSettle();
}

void main() {
  test('legacy archive footer validates links and rejects malformed or unsafe input', () {
    final page = _page('one', link: 'two');
    expect(
      archivedWebLinks(page.archiveText).single.uri.toString(),
      'https://example.org/two',
    );
    expect(
      archivedWebLinks('Body\n\nПосилання:\nRun\njavascript:alert(1)'),
      isEmpty,
    );
    expect(archivedWebLinks('Body\n\nПосилання:\nOdd'), isEmpty);
    expect(
      archivedWebLinks(
        'Body\n\nПосилання:\nFile\nfile:///tmp/x\nSafe\nhttps://example.org/a#b',
      ).single.uri.path,
      '/a',
    );
    expect(
      archivedWebLinks(
        'Body\n\nПосилання:\n${List.filled(31, 'x\nhttps://example.org/a').join('\n')}',
      ),
      isEmpty,
    );
  });

  testWidgets(
    'cached address and links use no fetch; missing link needs consent; history keeps both kinds',
    (tester) async {
      final f = (await tester.runAsync(openTestStore))!;
      final reader = _Reader();
      try {
        await tester.runAsync(() async {
          await f.store.saveWebPage(_page('one', link: 'two'));
          await f.store.saveWebPage(_page('two', link: 'missing'));
        });
        await tester.pumpWidget(
          MaterialApp(
            home: BrowserScreen(store: f.store, reader: reader),
          ),
        );
        await _go(tester, 'https://example.org/folder/../one#part');
        expect(find.text('Збережено на пристрої'), findsOneWidget);
        await _link(tester, 'Перейти до two');
        expect(find.text('two'), findsOneWidget);
        expect(reader.requests, isEmpty);
        await _link(tester, 'Перейти до missing');
        expect(find.text('Сторінку не збережено'), findsOneWidget);
        expect(reader.requests, isEmpty);
        await tester.tap(find.text('Залишитися офлайн'));
        await tester.pumpAndSettle();
        expect(reader.requests, isEmpty);
        await _link(tester, 'Перейти до missing');
        await tester.tap(find.text('Завантажити через інтернет'));
        await tester.pumpAndSettle();
        expect(reader.requests, ['https://example.org/missing']);
        expect(find.text('Отримано через інтернет'), findsOneWidget);
        await tester.tap(find.byTooltip('Попередня сторінка'));
        await tester.pumpAndSettle();
        expect(find.text('two'), findsOneWidget);
        expect(find.text('Збережено на пристрої'), findsOneWidget);
        await tester.tap(find.byTooltip('Попередня сторінка'));
        await tester.pumpAndSettle();
        expect(find.text('one'), findsOneWidget);
        await tester.tap(find.byTooltip('Наступна сторінка'));
        await tester.pumpAndSettle();
        expect(find.text('two'), findsOneWidget);
        expect(reader.requests, hasLength(1));
        await tester.tap(find.byTooltip('Завантажити свіжу сторінку'));
        await tester.pumpAndSettle();
        expect(reader.requests.last, 'https://example.org/two');
        expect(reader.requests, hasLength(2));
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

  testWidgets(
    'late network reply cannot replace cached selection; external launcher rejects unsafe URL and reports failure',
    (tester) async {
      final f = (await tester.runAsync(openTestStore))!;
      final reader = _Reader()..pending = Completer<ReaderPage>();
      final launched = <Uri>[];
      try {
        await tester.runAsync(() => f.store.saveWebPage(_page('cached')));
        await tester.pumpWidget(
          MaterialApp(
            home: BrowserScreen(
              store: f.store,
              reader: reader,
              launchExternal: (uri) async {
                launched.add(uri);
                return false;
              },
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('browser-address')),
          'https://example.org/slow',
        );
        await tester.tap(find.byTooltip('Відкрити адресу'));
        await tester.pump();
        await _go(tester, 'https://example.org/cached');
        reader.pending!.complete(_page('late'));
        await tester.pumpAndSettle();
        expect(find.text('cached'), findsOneWidget);
        expect(find.text('late'), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('browser-address')),
          'javascript:alert(1)',
        );
        await tester.tap(find.byTooltip('Відкрити у системному браузері'));
        await tester.pumpAndSettle();
        expect(launched, isEmpty);
        ScaffoldMessenger.of(tester.element(find.byType(BrowserScreen)))
            .removeCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('browser-address')),
          'example.org/cached#part',
        );
        await tester.tap(find.byTooltip('Відкрити у системному браузері'));
        await tester.pumpAndSettle();
        expect(launched.single.toString(), 'https://example.org/cached');
        expect(
          find.textContaining('Не вдалося передати адресу браузеру'),
          findsOneWidget,
        );
        expect(reader.requests, hasLength(1));
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
      'offline library full-text search, clear, favorites, sort and deletion at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final f = (await tester.runAsync(openTestStore))!;
        try {
          await tester.runAsync(() async {
            await f.store.saveWebPage(
              _page('Alpha', text: 'ХвойнийУнікальнийЛіс'),
            );
            await f.store.saveWebPage(
              _page('Beta', text: 'РічковаУнікальнаДолина'),
            );
            final alpha = f.store.articles.singleWhere(
              (a) => a.source.endsWith('/Alpha'),
            );
            await f.store.toggleFavorite(alpha.key);
          });
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: SavedPagesScreen(store: f.store),
            ),
          );
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('saved-pages-search')),
            'ХвойнийУнікальнийЛіс',
          );
          await tester.pump(const Duration(milliseconds: 200));
          await tester.runAsync(() async {
            await f.store.search('ХвойнийУнікальнийЛіс');
          });
          await tester.pumpAndSettle();
          expect(find.text('Alpha'), findsOneWidget);
          expect(find.text('Beta'), findsNothing);
          await tester.tap(find.byTooltip('Очистити пошук'));
          await tester.pumpAndSettle();
          expect(find.text('Beta'), findsOneWidget);
          await tester.tap(find.text('Лише обране'));
          await tester.pumpAndSettle();
          expect(find.text('Beta'), findsNothing);
          expect(find.text('Alpha'), findsOneWidget);
          await tester.tap(find.text('Лише обране'));
          await tester.tap(find.byTooltip('Порядок сторінок'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is CheckedPopupMenuItem<bool> && widget.value == true,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(find.text('Alpha')).dy,
            lessThan(tester.getTopLeft(find.text('Beta')).dy),
          );
          await tester.runAsync(() async {
            await tester.tap(
              find.byTooltip('Видалити збережену сторінку').first,
            );
            await f.store.flush();
          });
          await tester.pumpAndSettle();
          expect(find.text('Alpha'), findsNothing);
          expect(f.store.favoriteKeys, isEmpty);
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
  }
}
