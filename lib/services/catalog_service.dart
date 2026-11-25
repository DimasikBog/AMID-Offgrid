import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/catalog.dart';
import '../models/data.dart';
import 'atlas_storage.dart';
import 'document_codec.dart';
import 'backup_codec.dart';
import 'importer.dart';
import 'store.dart';

class CatalogService extends ChangeNotifier {
  CatalogService(
    this.store,
    this.files, {
    Future<List<CatalogEntry>>? catalogue,
    http.Client Function()? clientFactory,
  }) : atlas = AtlasStorage(store.backend.directory),
       entries = catalogue ?? loadCatalog(),
       _clientFactory = clientFactory ?? http.Client.new;
  final AppStore store;
  final ImportService files;
  final AtlasStorage atlas;
  final Future<List<CatalogEntry>> entries;
  final http.Client Function() _clientFactory;
  http.Client? _client;
  bool busy = false, _disposed = false;
  double progress = 0;
  String label = '';
  int _request = 0;
  bool installed(CatalogEntry e) =>
      store.packs.any((p) => p['id'] == e.id && p['sha256'] == e.sha256);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    _request++;
    _client?.close();
    files.cancel();
  }

  Future<void> install(CatalogEntry entry) async {
    if (_disposed || busy || files.busy) {
      throw StateError('Дочекайся завершення попереднього завантаження.');
    }
    // Claim the operation before any await, including the catalogue load.
    busy = true;
    progress = 0;
    label = 'Завантажую ${entry.title}';
    final ticket = ++_request;
    _changed();
    void check() {
      if (_disposed || ticket != _request) throw const OperationCancelled();
    }

    try {
      final catalogue = await entries;
      check();
      if (!catalogue.any((e) => identical(e, entry))) {
        throw const FormatException('Пакет відсутній у перевіреному каталозі.');
      }
      if (!entry.installable) {
        throw const FormatException(
          'Це джерело для пошуку, а не готовий пакет.',
        );
      }
      if (installed(entry)) return;
      if (store.packs.any((p) => p['id'] == entry.id)) {
        throw const FormatException(
          'Спочатку видали попередню версію цього пакета.',
        );
      }
      if (entry.model) {
        await files.installCatalogModel(entry);
        check();
        return;
      }
      _client = _clientFactory();
      final request = http.Request('GET', entry.url!)..followRedirects = false;
      final response = await _client!
          .send(request)
          .timeout(const Duration(seconds: 30));
      check();
      if (response.statusCode != 200 ||
          (response.contentLength != null &&
              response.contentLength != entry.bytes)) {
        throw const FormatException('Джерело повідомило інший розмір файла.');
      }
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 45),
      )) {
        check();
        received += chunk.length;
        if (received > entry.bytes) {
          throw const FormatException('Файл завеликий.');
        }
        builder.add(chunk);
        progress = received / entry.bytes;
        _changed();
      }
      final bytes = builder.takeBytes();
      check();
      if (bytes.length != entry.bytes ||
          sha256.convert(bytes).toString() != entry.sha256) {
        throw const FormatException(
          'Контрольна сума не збігається. Файл не встановлено.',
        );
      }
      if (entry.kind == 'geojson') {
        final pack = documentPack(
          decodeObject(utf8.decode(bytes)),
          entry.title,
        );
        pack['id'] = entry.id;
        pack['title'] = entry.title;
        pack['license'] = entry.license;
        pack['sha256'] = entry.sha256;
        pack['bytes'] = entry.bytes;
        await store.importKnowledge(pack, checkActive: check);
      } else {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        ui.ImageDescriptor? descriptor;
        try {
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          if (descriptor.width > 8192 ||
              descriptor.height > 8192 ||
              descriptor.width * descriptor.height > 24000000) {
            throw const FormatException('Роздільність карти перевищує ліміт.');
          }
        } finally {
          descriptor?.dispose();
          buffer.dispose();
        }
        check();
        await atlas.put(entry.id, bytes);
        try {
          check();
          await store.addAsset({
            'id': entry.id,
            'title': entry.title,
            'kind': 'atlas',
            'bytes': entry.bytes,
            'sha256': entry.sha256,
            'license': entry.license,
            'source': entry.source,
            'year': entry.year,
          }, checkActive: check);
        } catch (_) {
          await atlas.delete(entry.id);
          rethrow;
        }
      }
      label = 'Збережено для роботи без мережі';
      progress = 1;
    } finally {
      _client?.close();
      _client = null;
      busy = false;
      _changed();
    }
  }

  Future<Uint8List> image(CatalogEntry entry) async {
    final data = await atlas.read(entry.id);
    if (data == null ||
        data.length != entry.bytes ||
        sha256.convert(data).toString() != entry.sha256) {
      throw const FormatException(
        'Збережена карта відсутня або пошкоджена. Видали її та встанови повторно.',
      );
    }
    return data;
  }

  Future<void> remove(CatalogEntry entry) async {
    if (busy || files.busy) throw StateError('Спочатку заверши завантаження.');
    if (entry.kind == 'image') await atlas.delete(entry.id);
    await store.removePack(entry.id);
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    atlas.dispose();
    super.dispose();
  }
}
