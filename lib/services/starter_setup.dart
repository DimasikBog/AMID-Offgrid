import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/data.dart';
import '../models/starter_content.dart';
import 'importer.dart';
import 'backup_codec.dart';
import 'store.dart';

/// Full builds install their bundled model without making a network request.
/// Source/light builds download only after the user presses the setup button.
class StarterSetup extends ChangeNotifier {
  StarterSetup(this.store, this.files, {AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle {
    files.addListener(_changed);
    store.addListener(_storeChanged);
  }
  final AppStore store;
  final ImportService files;
  final AssetBundle _bundle;
  Future<void>? _initialization;
  StarterCatalog? catalog;
  bool initialized = false, initializing = false, installing = false;
  bool mapReady = false, knowledgeReady = false, modelReady = false;
  bool bundled = false,
      paused = false,
      _disposed = false,
      _pauseRequested = false;
  String? error;
  bool get busy => initializing || installing || files.busy;
  bool get ready =>
      error == null && mapReady && knowledgeReady && (kIsWeb || modelReady);

  void _storeChanged() {
    if (modelReady && !store.packs.any((p) => p['id'] == starterModelId)) {
      modelReady = false;
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    initializing = true;
    _changed();
    try {
      catalog = await files.starterCatalog;
      await _checkBase();
      if (_disposed) return;
      modelReady = !kIsWeb && await files.starterAvailable();
      if (modelReady && store.selectedModel.isEmpty && !_disposed) {
        await store.selectModel(starterModelId);
      }
      bundled = !kIsWeb && await files.hasBundledStarter();
      if (!_disposed && bundled && !modelReady && store.starterAutoSetup) {
        await _install(allowNetwork: false);
      }
    } catch (e) {
      if (!_disposed) error = 'Не вдалося підготувати набір: $e';
    } finally {
      initializing = false;
      initialized = true;
      _changed();
    }
  }

  Future<void> _checkBase() async {
    mapReady = false;
    knowledgeReady = false;
    final spec = catalog!;
    Future<Json> read(StarterAsset asset) async {
      final data = await _bundle.load(asset.path);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.length != asset.bytes ||
          sha256.convert(bytes).toString() != asset.sha256) {
        throw FormatException('Пошкоджений вбудований файл: ${asset.title}');
      }
      return decodeObject(utf8.decode(bytes));
    }

    final map = await read(spec.map);
    mapReady =
        map['type'] == 'FeatureCollection' &&
        (map['features'] as List).isNotEmpty;
    final knowledge = await read(spec.knowledge);
    knowledgeReady =
        knowledge['format'] == 'AMID_OFFGRID_PACK' &&
        store.packs.any((p) => p['id'] == AppStore.starterId) &&
        store.articles.any((a) => a.packId == AppStore.starterId);
    if (!mapReady || !knowledgeReady) {
      throw const FormatException('Базова карта або довідник не готові.');
    }
  }

  Future<void> install({bool repair = false}) async {
    await initialize();
    if (_disposed || installing || kIsWeb) return;
    await _install(repair: repair);
  }

  Future<void> _install({bool allowNetwork = true, bool repair = false}) async {
    installing = true;
    paused = false;
    _pauseRequested = false;
    error = null;
    _changed();
    try {
      await _checkBase();
      if (_disposed || _pauseRequested) throw const OperationCancelled();
      await files.prepareStarter(allowNetwork: allowNetwork, repair: repair);
    } on OperationCancelled {
      if (!_disposed) paused = true;
    } catch (e) {
      if (!_disposed) error = 'Встановлення не завершено: $e';
    } finally {
      if (!_disposed) {
        try {
          modelReady = await files.starterAvailable();
        } catch (_) {
          modelReady = false;
        }
      }
      installing = false;
      if (modelReady) paused = false;
      _changed();
    }
  }

  void pause() {
    _pauseRequested = true;
    files.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    if (installing) files.cancel();
    files.removeListener(_changed);
    store.removeListener(_storeChanged);
    super.dispose();
  }
}
