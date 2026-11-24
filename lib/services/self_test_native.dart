import 'dart:io';

import 'backend_native.dart';
import 'store.dart';
import 'importer_native.dart';
import 'starter_setup.dart';
import 'assistant_native.dart';
import '../models/starter_content.dart';

/// Invoked explicitly by desktop CI. Never opens or modifies personal data.
Future<void> runSelfTest({bool full = false}) async {
  final root = await Directory.systemTemp.createTemp('amid-self-test-');
  AppStore? store;
  ImportService? files;
  StarterSetup? setup;
  AssistantService? assistant;
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
    if (full) {
      files = ImportService(store);
      if (!await files.hasBundledStarter()) {
        throw StateError('The full probe requires a bundled model');
      }
      setup = StarterSetup(store, files);
      await setup.initialize();
      if (!setup.ready ||
          setup.error != null ||
          store.selectedModel != starterModelId) {
        throw StateError('Automatic offline setup failed: ${setup.error}');
      }
      assistant = AssistantService(store);
      await assistant
          .ask('Reply with the word OK only.')
          .timeout(const Duration(minutes: 3));
      if (!assistant.generated ||
          assistant.answer.trim().isEmpty ||
          assistant.error != null ||
          !assistant.ready) {
        throw StateError('Local model inference failed: ${assistant.error}');
      }
      stdout.writeln(
        'AMID_FULL_SETUP_OK: bundled map and knowledge verified, model installed, first-question local inference produced ${assistant.answer.length} characters',
      );
      await assistant.unload();
    }
  } catch (error) {
    stderr.writeln('AMID_SELF_TEST_FAILED: $error');
    code = 1;
  } finally {
    assistant?.dispose();
    setup?.dispose();
    files?.dispose();
    await store?.close();
    await root.delete(recursive: true);
  }
  exit(code);
}
