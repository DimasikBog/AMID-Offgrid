import 'dart:async';
import 'dart:io';

import 'package:amid_offgrid/models/data.dart';
import 'package:amid_offgrid/services/assistant_native.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppStore store;
  setUp(() async {
    final pair = await openTestStore();
    root = pair.root;
    store = pair.store;
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });
  test(
    'rapid asks do not interleave questions while retrieval is pending',
    () async {
      final found = Completer<List<Article>>();
      final ai = AssistantService(store, findSources: (_) => found.future);
      final first = ai.ask('Перше питання');
      await ai.ask('Друге питання');
      expect(ai.question, 'Перше питання');
      expect(ai.searching, true);
      found.complete([]);
      await first;
      expect(ai.busy, false);
      ai.dispose();
    },
  );
  test('cancelled retrieval cannot overwrite a newer request', () async {
    final found = Completer<List<Article>>();
    var count = 0;
    final ai = AssistantService(
      store,
      findSources: (_) => count++ == 0 ? found.future : Future.value([]),
    );
    final old = ai.ask('Старе питання');
    await ai.cancel();
    await ai.ask('Нове питання');
    found.complete([store.articles.first]);
    await old;
    expect(ai.question, 'Нове питання');
    expect(ai.sources, isEmpty);
    expect(ai.busy, false);
    ai.dispose();
  });
  test(
    'retrieval failure is shown as an error and releases controls',
    () async {
      final ai = AssistantService(
        store,
        findSources: (_) => Future.error(StateError('Сховище недоступне')),
      );
      await ai.ask('Запит');
      expect(ai.error, contains('Сховище недоступне'));
      expect(ai.busy, false);
      ai.dispose();
    },
  );
  test(
    'disposing during retrieval does not notify a disposed listener',
    () async {
      final found = Completer<List<Article>>();
      final ai = AssistantService(store, findSources: (_) => found.future);
      var notifications = 0;
      ai.addListener(() => notifications++);
      final request = ai.ask('Запит');
      ai.dispose();
      final before = notifications;
      found.complete([]);
      await request;
      expect(notifications, before);
    },
  );
}
