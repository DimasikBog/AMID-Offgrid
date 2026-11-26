import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/street_map.dart';
import 'atlas_storage.dart';
import 'backup_codec.dart';
import 'store.dart';
import 'street_http_client.dart';

typedef StreetProviderOpener = Future<vt.VectorTileProvider> Function(
  http.Client client,
);

class StreetService extends ChangeNotifier {
  StreetService(
    this.store, {
    AtlasStorage? storage,
    StreetProviderOpener? opener,
    http.Client Function()? clientFactory,
  }) : storage =
           storage ?? AtlasStorage(store.backend.directory, scope: 'streets'),
       _opener = opener ?? _open,
       _clientFactory = clientFactory ?? http.Client.new;
  final AppStore store;
  final AtlasStorage storage;
  final StreetProviderOpener _opener;
  final http.Client Function() _clientFactory;
  Future<void>? _ready;
  vt.VectorTileProvider? provider;
  StreetHttpClient? _viewClient, _downloadClient;
  vt.CancellationToken? _downloadToken;
  String mode = 'overview', label = '', dataDate = '';
  String? error;
  bool loading = false, busy = false, _disposed = false;
  double progress = 0;
  int _viewEpoch = 0;

  static Future<vt.VectorTileProvider> _open(http.Client client) =>
      vt.PmTilesVectorTileProvider.open(
        streetArchiveUrl,
        client: client,
        maxRetries: 1,
      );
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> get ready => _ready ??= _prepare();
  Future<void> _prepare() async {
    final keep = {
      for (final region in store.streetRegions)
        for (final key in region.tileKeys) region.storageId(key),
    };
    try {
      await storage.prune(keep);
    } catch (_) {
      /* A read-only cache can still be viewed. */
    }
  }

  Future<void> selectMode(String value) async {
    if (_disposed) return;
    final epoch = ++_viewEpoch;
    provider?.dispose();
    provider = null;
    _viewClient?.close();
    _viewClient = null;
    mode = value;
    loading = value != 'overview';
    error = null;
    _changed();
    vt.VectorTileProvider? opened;
    void check() {
      if (_disposed || epoch != _viewEpoch) throw const OperationCancelled();
    }

    void tileFailed() {
      if (_disposed || epoch != _viewEpoch || error != null) return;
      error = value == 'online'
          ? 'Частина вулиць не завантажилася. Перевір мережу або вибери збережену область.'
          : 'Копія області неповна або пошкоджена. Завантаж її повторно.';
      _changed();
    }

    try {
      await ready;
      check();
      if (value == 'online') {
        final client = StreetHttpClient(inner: _clientFactory());
        _viewClient = client;
        final raw = await _opener(client);
        opened = _OnlineProvider(raw, client.etag ?? 'snapshot', tileFailed);
        check();
        dataDate = client.dataDate ?? '';
      } else if (value != 'overview') {
        final region = store.streetRegions
            .where((r) => r.id == value)
            .firstOrNull;
        if (region == null) {
          throw const FormatException('Збережену область не знайдено.');
        }
        opened = SavedStreetProvider(region, storage, onError: tileFailed);
        dataDate = region.data['dataDate'] as String? ?? '';
      }
      await store.setStreetMode(value, checkActive: check);
      check();
      provider = opened;
      opened = null;
    } on OperationCancelled {
      /* A newer source owns the map now. */
    } catch (_) {
      if (epoch == _viewEpoch && !_disposed) {
        _viewClient?.close();
        _viewClient = null;
        error = 'Не вдалося відкрити детальну карту. Перевір інтернет або вибери збережену область.';
      }
    } finally {
      opened?.dispose();
      if (epoch == _viewEpoch) {
        loading = false;
        _changed();
      }
    }
  }

  Future<void> download(
    StreetBounds bounds,
    int maximumZoom,
    String title,
  ) async {
    if (_disposed || busy) {
      throw StateError('Попереднє завантаження ще триває.');
    }
    final name = title.trim();
    if (name.isEmpty || name.runes.length > 80) {
      throw const FormatException('Назва області: від 1 до 80 символів.');
    }
    final tiles = bounds.tiles(maximumZoom);
    if (store.streetRegions.length >= 12) {
      throw const FormatException('Спочатку видали непотрібну область.');
    }
    busy = true;
    progress = 0;
    label = 'Готую область';
    final originalViewEpoch = _viewEpoch;
    final token = vt.CancellationToken();
    _downloadToken = token;
    final id = const Uuid().v4(), written = <String>[];
    var committed = false, size = 0;
    vt.VectorTileProvider? source;
    final client = StreetHttpClient(inner: _clientFactory());
    _downloadClient = client;
    _changed();
    void check() {
      if (_disposed || token.isCancelled) throw const OperationCancelled();
    }

    try {
      await ready;
      check();
      source = await _opener(client);
      check();
      if (source.maximumZoom < maximumZoom) {
        throw const FormatException('Джерело не містить вибраного масштабу.');
      }
      final records = <String, dynamic>{};
      for (final tile in tiles) {
        check();
        final response = await source.load(
          vt.TileKey(tile.z, tile.x, tile.y),
          cancellation: token,
        );
        check();
        final Uint8List bytes;
        if (response is vt.TileResponseData) {
          bytes = response.bytes;
        } else if (response is vt.TileResponseNotFound) {
          bytes = Uint8List(0);
        } else {
          throw StateError(
            'Завантаження перерване. Область не буде позначено готовою.',
          );
        }
        size += bytes.length;
        if (bytes.length > 2 * 1024 * 1024 ||
            size > maxStreetBytes ||
            size + store.streetRegions.fold<int>(0, (n, r) => n + r.bytes) >
                maxStreetStorageBytes) {
          throw const FormatException(
            'Область завелика для офлайн-збереження. Наблизь карту або зменш деталізацію.',
          );
        }
        final key = 'street-$id-${tile.key}';
        if (bytes.isNotEmpty) {
          written.add(key);
          await storage.put(key, bytes);
          check();
        }
        records[tile.key] = {
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        };
        progress = records.length / tiles.length;
        label =
            '${records.length}/${tiles.length} · ${(size / 1048576).toStringAsFixed(1)} MiB';
        _changed();
      }
      check();
      final metadata = <String, dynamic>{
        'id': id,
        'title': name,
        'source': streetArchiveUrl,
        'dataDate': client.dataDate ?? '',
        'bounds': bounds.json,
        'maxZoom': maximumZoom,
        'tiles': records,
        'bytes': size,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      await store.saveStreetRegion(metadata, checkActive: check);
      committed = true;
      if (!_disposed && _viewEpoch == originalViewEpoch) await selectMode(id);
    } catch (e) {
      if (token.isCancelled || _disposed) throw const OperationCancelled();
      if (e is http.ClientException || e is TimeoutException) {
        throw StateError(
          'З’єднання з джерелом карти перерване. Область не позначено готовою — спробуй ще раз.',
        );
      }
      rethrow;
    } finally {
      source?.dispose();
      client.close();
      if (!committed) {
        for (final key in written) {
          try {
            await storage.delete(key);
          } catch (_) {}
        }
      }
      _downloadClient = null;
      _downloadToken = null;
      busy = false;
      _changed();
    }
  }

  void cancelDownload() {
    _downloadToken?.cancel();
    _downloadClient?.close();
    if (busy) {
      label = 'Скасовую завантаження…';
      _changed();
    }
  }

  Future<void> delete(StreetRegion region) async {
    if (busy) throw StateError('Дочекайся завершення завантаження.');
    if (mode == region.id) await selectMode('overview');
    await store.deleteStreetRegion(region.id);
    for (final key in region.tileKeys) {
      await storage.delete(region.storageId(key));
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _viewEpoch++;
    cancelDownload();
    provider?.dispose();
    _viewClient?.close();
    storage.dispose();
    super.dispose();
  }
}

class _OnlineProvider extends vt.VectorTileProvider {
  _OnlineProvider(this.inner, this.version, this.onError);
  final vt.VectorTileProvider inner;
  final String version;
  final VoidCallback onError;
  @override
  int get maximumZoom => inner.maximumZoom;
  @override
  int get minimumZoom => inner.minimumZoom;
  @override
  String get cacheKey => '${inner.cacheKey}:$version';
  @override
  bool get cacheBytesToDisk => false;
  @override
  Future<vt.TileResponse> load(
    vt.TileKey tile, {
    vt.CancellationToken? cancellation,
  }) async {
    final result = await inner.load(tile, cancellation: cancellation);
    if (result is vt.TileResponseError) onError();
    return result;
  }

  @override
  void dispose() => inner.dispose();
}

class SavedStreetProvider extends vt.VectorTileProvider {
  SavedStreetProvider(this.region, this.storage, {this.onError});
  final StreetRegion region;
  final AtlasStorage storage;
  final VoidCallback? onError;
  bool _disposed = false;
  final _loads = vt.SingleFlight<String, vt.TileResponse>();
  @override
  int get maximumZoom => region.maxZoom;
  @override
  int get minimumZoom => 0;
  @override
  String get cacheKey => 'AMID-street-region:${region.id}';
  @override
  bool get cacheBytesToDisk => false;
  @override
  Future<vt.TileResponse> load(
    vt.TileKey tile, {
    vt.CancellationToken? cancellation,
  }) => _loads.run('${tile.z}-${tile.x}-${tile.y}', (token) async {
    if (_disposed || token.isCancelled) return const vt.TileResponseCancelled();
    final key = '${tile.z}-${tile.x}-${tile.y}',
        record = (region.data['tiles'] as Map)[key];
    if (record is! Map || record['bytes'] == 0) {
      return const vt.TileResponseNotFound();
    }
    try {
      final bytes = await storage.read(region.storageId(key));
      if (_disposed || token.isCancelled) {
        return const vt.TileResponseCancelled();
      }
      if (bytes == null ||
          bytes.length != record['bytes'] ||
          sha256.convert(bytes).toString() != record['sha256']) {
        onError?.call();
        return vt.TileResponseError(
          StateError('Копія карти пошкоджена. Завантаж область повторно.'),
        );
      }
      return vt.TileResponseData(bytes);
    } catch (e) {
      onError?.call();
      return vt.TileResponseError(e);
    }
  }, cancellation: cancellation);
  @override
  void dispose() {
    _disposed = true;
    _loads.clear();
  }
}
