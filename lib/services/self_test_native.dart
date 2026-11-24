import 'dart:io';

import 'backend_native.dart';
import 'store.dart';

/// Invoked explicitly by desktop CI. Never opens or modifies personal data.
Future<void> runSelfTest() async {
  final root = await Directory.systemTemp.createTemp('amid-self-test-');
  AppStore? store;
  var code = 0;
  try {
    store = await AppStore.open(
      backend: await PlatformBackend.open(root: root),
    );
    await store.saveNote(
      title: 'AMID self-test',
      body: 'Local SQLite persistence',
    );
    await store.setReaderScale(1.3);
    await store.setPrepared('backup', true);
    await store.close();
    store = await AppStore.open(
      backend: await PlatformBackend.open(root: root),
    );
    final matches = await store.search('persistence');
    if (!matches.any((a) => a.title == 'AMID self-test') ||
        store.readerScale != 1.3 ||
        !store.preparation.contains('backup')) {
      throw StateError('Persistence verification failed');
    }
    stdout.writeln('AMID_SELF_TEST_OK');
  } catch (error) {
    stderr.writeln('AMID_SELF_TEST_FAILED: $error');
    code = 1;
  } finally {
    await store?.close();
    await root.delete(recursive: true);
  }
  exit(code);
}
