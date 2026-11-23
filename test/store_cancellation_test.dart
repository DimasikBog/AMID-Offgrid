import 'dart:async';
import 'dart:io';

import 'package:amid_offgrid/models/data.dart';
import 'package:amid_offgrid/services/backend_native.dart';
import 'package:amid_offgrid/services/backup_codec.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _GateBackend implements PlatformBackend {
  _GateBackend(this.inner);
  final PlatformBackend inner;
  Completer<void>? entered, release;
  @override
  Database get db => inner.db;
  @override
  String get directory => inner.directory;
  @override
  Future<Json?> load() => inner.load();
  @override
  Future<void> close() => inner.close();
  @override
  Future<List<String>> searchKeys(String query, int limit) =>
      inner.searchKeys(query, limit);
  @override
  Future<void> save(Json value, {bool reindex = false}) async {
    if (entered != null && !entered!.isCompleted) {
      entered!.complete();
      await release!.future;
    }
    await inner.save(value, reindex: reindex);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final kind in ['knowledge', 'asset', 'restore']) {
    test(
      'cancelled $kind does not commit after waiting behind another write',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'amid-queue-cancel-',
        );
        final backend = _GateBackend(
          await PlatformBackend.open(factory: databaseFactoryFfi, root: root),
        );
        final store = await AppStore.open(
          backend: backend,
          seedText: File('assets/starter.json').readAsStringSync(),
        );
        try {
          backend.entered = Completer<void>();
          backend.release = Completer<void>();
          final first = store.savePin(
            const Pin('first', 'Перший запис', 48, 22),
          );
          await backend.entered!.future;
          var cancelled = false;
          void check() {
            if (cancelled) throw const OperationCancelled();
          }

          final rawPack = <String, dynamic>{
            'format': 'AMID_OFFGRID_PACK',
            'version': 1,
            'id': 'late-pack',
            'title': 'Пізній пакет',
            'license': 'Власний',
            'articles': [],
          };
          final operation = switch (kind) {
            'knowledge' => store.importKnowledge(
              parsePack(rawPack),
              checkActive: check,
            ),
            'asset' => store.addAsset({
              'id': 'late-model',
              'kind': 'model',
              'title': 'Модель',
            }, checkActive: check),
            _ => store.restore({
              'format': 'AMID_OFFGRID_BACKUP',
              'version': 1,
              'packs': [rawPack],
              'pins': [],
              'messages': [],
              'draft': 'Не додавати',
            }, checkActive: check),
          };
          final observed = operation.then<Object?>(
            (_) => null,
            onError: (Object error) => error,
          );
          cancelled = true;
          backend.release!.complete();
          await first;
          expect(await observed, isA<OperationCancelled>());
          expect(store.pins.single.id, 'first');
          expect(
            store.packs.any(
              (p) => p['id'] == 'late-pack' || p['id'] == 'late-model',
            ),
            isFalse,
          );
          expect(store.draft, isEmpty);
          expect(store.selectedModel, isEmpty);
          await store.setDraft('Наступний запис працює');
          expect((await backend.load())!['draft'], 'Наступний запис працює');
        } finally {
          if (backend.release != null && !backend.release!.isCompleted) {
            backend.release!.complete();
          }
          await store.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
