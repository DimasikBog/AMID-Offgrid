import 'package:amid_offgrid/models/web_page.dart';
import 'package:amid_offgrid/services/backend_native.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

ReaderPage _page(String path, String text) => ReaderPage.fromHtml(
  '<title>$path</title><p>$text</p>',
  Uri.parse('https://example.org/$path'),
  receivedBytes: 100,
);

void main() {
  test('pages survive reopen, enter search, update without duplicates and delete with favorites', () async {
    final f = await openTestStore();
    AppStore store = f.store;
    try {
      await store.saveWebPage(_page('maps', 'УнікальнийТекстКарт'));
      final page = store.articles.singleWhere(
        (a) => a.packId == AppStore.webPagesId,
      );
      await store.toggleFavorite(page.key);
      await store.saveWebPage(_page('maps', 'ОновленийТекстКарт'));
      expect(
        store.articles.where((a) => a.packId == AppStore.webPagesId),
        hasLength(1),
      );
      expect(store.favoriteKeys, contains(page.key));
      await store.close();
      store = await AppStore.open(
        backend: await PlatformBackend.open(
          factory: databaseFactoryFfi,
          root: f.root,
        ),
      );
      expect(
        (await store.search('ОновленийТекстКарт')).single.source,
        'https://example.org/maps',
      );
      expect(await store.search('УнікальнийТекстКарт'), isEmpty);
      await store.deleteWebPage(page.key);
      expect(store.packs.where((p) => p['id'] == AppStore.webPagesId), isEmpty);
      expect(store.favoriteKeys, isNot(contains(page.key)));
    } finally {
      await store.close();
      await f.root.delete(recursive: true);
    }
  });

  test('backup merges missing pages into an existing collection, preserving local edits', () async {
    final source = await openTestStore(), target = await openTestStore();
    try {
      await source.store.saveWebPage(_page('one', 'Резервна перша'));
      await source.store.saveWebPage(_page('two', 'Резервна друга'));
      await target.store.saveWebPage(_page('one', 'Моя новіша перша'));
      await target.store.restore(source.store.backup());
      final saved = target.store.articles
          .where((a) => a.packId == AppStore.webPagesId)
          .toList();
      expect(saved, hasLength(2));
      expect(
        saved.singleWhere((p) => p.source.endsWith('/one')).body,
        contains('Моя новіша перша'),
      );
      expect(
        saved.singleWhere((p) => p.source.endsWith('/two')).body,
        contains('Резервна друга'),
      );
      expect(
        target.store.packs.singleWhere(
          (p) => p['id'] == AppStore.webPagesId,
        )['count'],
        2,
      );
    } finally {
      await source.store.close();
      await target.store.close();
      await source.root.delete(recursive: true);
      await target.root.delete(recursive: true);
    }
  });
}
