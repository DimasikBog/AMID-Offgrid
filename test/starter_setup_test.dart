import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amid_offgrid/models/starter_content.dart';
import 'package:amid_offgrid/services/assistant_native.dart';
import 'package:amid_offgrid/services/backup_codec.dart';
import 'package:amid_offgrid/services/importer_native.dart';
import 'package:amid_offgrid/services/starter_setup.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:amid_offgrid/widgets/starter_setup_panel.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

class FixtureBundle extends AssetBundle {
  FixtureBundle(this.payload, {bool bundled = true}) {
    for (final path in ['assets/world.geojson', 'assets/starter.json']) {
      data[path] = File(path).readAsBytesSync();
    }
    final catalog = jsonDecode(
      File('$starterAssetDirectory/catalog.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    catalog['model'] = Map<String, dynamic>.from(catalog['model'] as Map)
      ..addAll({
        'bytes': payload.length,
        'sha256': sha256.convert(payload).toString(),
      });
    data['$starterAssetDirectory/catalog.json'] = utf8.encode(
      jsonEncode(catalog),
    );
    data['$starterAssetDirectory/bundle.json'] = utf8.encode(
      jsonEncode({
        'format': 'AMID_BUNDLED_MODEL',
        'version': 1,
        'included': bundled,
        'bytes': payload.length,
        'sha256': sha256.convert(payload).toString(),
        'chunkBytes': 8,
        'parts': (payload.length + 7) ~/ 8,
      }),
    );
    for (var i = 0; i * 8 < payload.length; i++) {
      data['$starterAssetDirectory/model-${i.toString().padLeft(3, '0')}.part'] =
          payload.sublist(i * 8, ((i + 1) * 8).clamp(0, payload.length));
    }
  }
  final List<int> payload;
  final data = <String, List<int>>{};
  final reads = <String>[];
  void Function(String)? onRead;
  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    onRead?.call(key);
    final bytes = data[key];
    if (bytes == null) throw StateError('Missing fixture asset $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

class RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = utf8.encode('GGUF deterministic model installation fixture');
  late Directory root;
  late AppStore store;
  late FixtureBundle bundle;
  late ImportService files;
  late StarterSetup setup;

  setUp(() async {
    final f = await openTestStore();
    root = f.root;
    store = f.store;
    bundle = FixtureBundle(bytes);
    files = ImportService(
      store,
      bundle: bundle,
      clientFactory: () =>
          throw StateError('A full build must never access the network'),
    );
    setup = StarterSetup(store, files, bundle: bundle);
  });
  tearDown(() async {
    setup.dispose();
    files.dispose();
    await store.close();
    await root.delete(recursive: true);
  });

  test('full bundle installs automatically, verifies bytes and survives repeated initialization', () async {
    await setup.initialize();
    expect(setup.error, isNull);
    expect(setup.ready, true);
    final model = store.packs.singleWhere((p) => p['id'] == starterModelId);
    expect(await File(model['path'] as String).readAsBytes(), bytes);
    expect(store.selectedModel, starterModelId);
    final reads = bundle.reads.length;
    await setup.initialize();
    expect(bundle.reads.length, reads);
    expect(store.packs.where((p) => p['id'] == starterModelId), hasLength(1));
  });

  test('pause between bundled chunks retains a prefix and resumes without re-reading it', () async {
    final second = '$starterAssetDirectory/model-001.part';
    bundle.onRead = (key) {
      if (key == second) files.cancel();
    };
    await setup.initialize();
    expect(setup.paused, true);
    expect(setup.ready, false);
    expect(store.packs.any((p) => p['id'] == starterModelId), false);
    final firstReads = bundle.reads
        .where((p) => p.endsWith('model-000.part'))
        .length;
    bundle.onRead = null;
    await setup.install();
    expect(setup.ready, true);
    expect(
      bundle.reads.where((p) => p.endsWith('model-000.part')).length,
      firstReads,
    );
  });

  test(
    'corrupt payload is never activated, then a corrected retry succeeds',
    () async {
      final part = '$starterAssetDirectory/model-001.part';
      final original = bundle.data[part]!;
      bundle.data[part] = List.filled(original.length, 0);
      await setup.initialize();
      expect(setup.ready, false);
      expect(setup.error, contains('Контрольна сума'));
      expect(store.packs.any((p) => p['id'] == starterModelId), false);
      bundle.data[part] = original;
      await setup.install();
      expect(setup.ready, true);
    },
  );

  test(
    'missing base map cannot be reported ready and never downloads a model',
    () async {
      bundle.data['assets/world.geojson'] = utf8.encode('{}');
      await setup.initialize();
      expect(setup.ready, false);
      expect(setup.mapReady, false);
      expect(setup.error, isNotNull);
      expect(bundle.reads.where((p) => p.endsWith('.part')), isEmpty);
    },
  );

  test('repair restores missing official bytes and preserves custom selection and notes', () async {
    await setup.initialize();
    await store.saveNote(title: 'Моя нотатка', body: 'Не видаляти');
    await store.addAsset({
      'id': 'custom-model',
      'title': 'Custom',
      'kind': 'model',
      'path': '/owned/custom.gguf',
    });
    final model = store.packs.firstWhere((p) => p['id'] == starterModelId);
    await File(model['path'] as String).delete();
    expect(await files.starterAvailable(), false);
    await setup.install(repair: true);
    expect(setup.ready, true);
    expect(store.selectedModel, 'custom-model');
    expect(store.articles.any((a) => a.title == 'Моя нотатка'), true);
    expect(store.packs.where((p) => p['id'] == starterModelId), hasLength(1));
    await store.removePack(starterModelId);
    expect(setup.modelReady, false);
  });

  test(
    'cancellation before queued activation leaves the old metadata intact',
    () async {
      await expectLater(
        store.installStarterModel({
          'id': starterModelId,
          'kind': 'model',
        }, checkActive: () => throw const OperationCancelled()),
        throwsA(isA<OperationCancelled>()),
      );
      expect(store.packs.any((p) => p['id'] == starterModelId), false);
    },
  );

  test('deliberately removed model is not reinstalled automatically', () async {
    await setup.initialize();
    await store.removePack(starterModelId);
    final count = bundle.reads.where((p) => p.endsWith('.part')).length;
    final reopenedSetup = StarterSetup(store, files, bundle: bundle);
    await reopenedSetup.initialize();
    expect(reopenedSetup.modelReady, false);
    expect(store.starterAutoSetup, false);
    expect(bundle.reads.where((p) => p.endsWith('.part')).length, count);
    await reopenedSetup.install();
    expect(reopenedSetup.ready, true);
    expect(store.starterAutoSetup, true);
    reopenedSetup.dispose();
  });

  test('saved but missing model produces an autoload error instead of a pretend AI answer', () async {
    await store.addAsset({
      'id': 'missing',
      'kind': 'model',
      'path': '${root.path}/missing.gguf',
    });
    final ai = AssistantService(store);
    await ai.ask('Привіт');
    expect(ai.generated, false);
    expect(ai.error, contains('Файл моделі відсутній'));
    expect(ai.busy, false);
    ai.dispose();
  });

  Future<(HttpServer, ImportService)> network(
    void Function(HttpRequest) respond,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(respond);
    final c = await files.starterCatalog;
    final remote = StarterCatalog(
      map: c.map,
      knowledge: c.knowledge,
      model: StarterModel(
        bytes: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        url: Uri.parse('http://127.0.0.1:${server.port}/model'),
        title: c.model.title,
        license: c.model.license,
      ),
    );
    final light = FixtureBundle(bytes, bundled: false);
    final importer = ImportService(
      store,
      bundle: light,
      catalogOverride: remote,
      clientFactory: () => RealHttp().createHttpClient(null),
    );
    addTearDown(() async {
      importer.dispose();
      await server.close(force: true);
    });
    return (server, importer);
  }

  test(
    'HTTP range resumes a partial model and activates only the complete digest',
    () async {
      String? range;
      final (_, importer) = await network((request) {
        range = request.headers.value('range');
        request.response.statusCode = 206;
        request.response.headers.set(
          'content-range',
          'bytes 7-${bytes.length - 1}/${bytes.length}',
        );
        request.response.contentLength = bytes.length - 7;
        request.response.add(bytes.sublist(7));
        request.response.close();
      });
      final partial = File('${root.path}/files/qwen3-06b-q8.gguf.partial');
      await partial.parent.create();
      await partial.writeAsBytes(bytes.sublist(0, 7));
      await importer.prepareStarter();
      expect(range, 'bytes=7-');
      expect(await importer.starterAvailable(), true);
      expect(
        await File('${root.path}/files/qwen3-06b-q8.gguf').readAsBytes(),
        bytes,
      );
    },
  );

  test('range-ignoring HTTP 200 restarts cleanly instead of appending duplicate bytes', () async {
    final (_, importer) = await network((request) {
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      request.response.close();
    });
    final partial = File('${root.path}/files/qwen3-06b-q8.gguf.partial');
    await partial.parent.create();
    await partial.writeAsBytes(bytes.sublist(0, 7));
    await importer.prepareStarter();
    expect(await importer.starterAvailable(), true);
  });

  test(
    'wrong range and wrong hash cannot activate a downloaded model',
    () async {
      var badRange = true;
      final (_, importer) = await network((request) {
        request.response.statusCode = badRange ? 206 : 200;
        if (badRange) {
          request.response.headers.set(
            'content-range',
            'bytes 1-${bytes.length - 1}/${bytes.length}',
          );
        }
        request.response.contentLength = bytes.length;
        request.response.add(List.filled(bytes.length, 0));
        request.response.close();
      });
      await expectLater(
        importer.prepareStarter(),
        throwsA(isA<HttpException>()),
      );
      badRange = false;
      await expectLater(importer.prepareStarter(), throwsFormatException);
      expect(await importer.starterAvailable(), false);
    },
  );

  test('cancel while awaiting HTTP headers completes promptly and leaves no active pack', () async {
    final arrived = Completer<void>();
    final (_, importer) = await network((request) {
      arrived.complete();
    });
    final action = importer.prepareStarter();
    final checked = expectLater(action, throwsA(isA<OperationCancelled>()));
    await arrived.future.timeout(const Duration(seconds: 5));
    importer.cancel();
    await checked.timeout(const Duration(seconds: 5));
    expect(await importer.starterAvailable(), false);
  });

  testWidgets('setup panel remains readable at 320px with doubled text', (
    tester,
  ) async {
    await tester.runAsync(setup.initialize);
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(child: StarterSetupPanel(setup: setup)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text('Набір установлено. Можна користуватися без інтернету.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
