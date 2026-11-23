import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amid_offgrid/services/backup_codec.dart';
import 'package:amid_offgrid/services/importer_native.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppStore store;
  late ImportService files;
  setUp(() async {
    final pair = await openTestStore();
    root = pair.root;
    store = pair.store;
    files = ImportService(store);
  });
  tearDown(() async {
    files.dispose();
    await store.close();
    await root.delete(recursive: true);
  });
  test(
    'long text import is complete and searchable instead of failing at 250k',
    () async {
      final text = List.filled(70000, 'Довгий документ\n').join();
      final bytes = utf8.encode(text);
      await files.importStream(
        'Текст.txt',
        bytes.length,
        () => Stream.value(bytes),
      );
      final imported = store.articles.where(
        (a) => a.packId.startsWith('text-'),
      );
      expect(imported.length, greaterThan(1));
      expect(imported.map((a) => a.body).join(), text);
      expect(await store.search('Довгий'), isNotEmpty);
    },
  );
  test('cancelling an import removes partial files and releases the operation lock', () async {
    final started = Completer<void>(),
        controller = StreamController<List<int>>();
    final operation = files.importStream('Model.gguf', 8, () {
      started.complete();
      return controller.stream;
    });
    final failed = expectLater(operation, throwsA(isA<OperationCancelled>()));
    await started.future;
    await expectLater(
      files.importStream('other.txt', 0, () => const Stream.empty()),
      throwsStateError,
    );
    files.cancel();
    controller.add([71, 71, 85, 70, 0, 0, 0, 0]);
    await controller.close();
    await failed;
    expect(files.busy, false);
    expect(store.packs.any((p) => p['kind'] == 'model'), false);
    expect(await Directory('${root.path}/files').list().toList(), isEmpty);
  });
  test('truncated text is rejected without modifying stored content', () async {
    final before = store.articles.length;
    await expectLater(
      files.importStream('bad.txt', 100, () => Stream.value([65])),
      throwsA(isA<FileSystemException>()),
    );
    expect(store.articles.length, before);
    expect(files.busy, false);
  });
  test(
    'cancellation releases a stalled source without another data event',
    () async {
      final listening = Completer<void>();
      var cancelled = false;
      final input = StreamController<List<int>>(
        onListen: () => listening.complete(),
        onCancel: () => cancelled = true,
      );
      final operation = files.importStream(
        'waiting.txt',
        1,
        () => input.stream,
      );
      final observed = operation.then<Object?>(
        (value) => value,
        onError: (Object e) => e,
      );
      try {
        await listening.future;
        files.cancel();
        final outcome = await observed.timeout(const Duration(seconds: 2));
        expect(outcome, isA<OperationCancelled>());
        expect(cancelled, isTrue);
        expect(files.busy, isFalse);
      } finally {
        // Wake the old implementation on failure so the regression test can close.
        if (!cancelled) input.add([65]);
        await input.close();
        await observed;
      }
    },
  );
  test(
    'encrypted import restores data only after the correct password',
    () async {
      const password = 'Мій захищений пароль 2026';
      final encrypted = await BackupCodec.encrypt({
        'format': 'AMID_OFFGRID_BACKUP',
        'version': 1,
        'packs': [],
        'messages': [],
        'pins': [],
        'draft': 'Приватна чернетка',
      }, password);
      final bytes = utf8.encode(jsonEncode(encrypted));
      await expectLater(
        files.importStream(
          'backup.amidbackup',
          bytes.length,
          () => Stream.value(bytes),
          requestPassword: () async => 'Інший невірний пароль',
        ),
        throwsFormatException,
      );
      expect(store.draft, '');
      await files.importStream(
        'backup.amidbackup',
        bytes.length,
        () => Stream.value(bytes),
        requestPassword: () async => password,
      );
      expect(store.draft, 'Приватна чернетка');
    },
  );
}
