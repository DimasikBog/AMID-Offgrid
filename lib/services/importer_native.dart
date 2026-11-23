import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/data.dart';
import 'backup_codec.dart';
import 'cancellable_reader.dart';
import 'document_codec.dart';
import 'raster_archive_native.dart';
import 'store.dart';

class ImportService extends ChangeNotifier {
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }

  ImportService(this.store);
  final AppStore store;
  final _reads = CancellableReader();
  bool busy = false, _cancelled = false;
  double progress = 0;
  String label = '';
  HttpClient? _client;
  static const _files = MethodChannel('com.amid.offgrid/files');
  static const starterId = 'qwen3-06b-q8';
  static const modelBytes = 639446688;
  static const modelHash =
      '9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031';
  static const modelUrl =
      'https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/23749fefcc72300e3a2ad315e1317431b06b590a/Qwen3-0.6B-Q8_0.gguf';
  void _report(double value, String text) {
    progress = value.clamp(0, 1);
    label = text;
    notifyListeners();
  }

  void _checkCancelled() {
    if (_cancelled || _disposed) throw const OperationCancelled();
  }

  Future<T> _run<T>(String description, Future<T> Function() action) async {
    if (_disposed) throw StateError('Сервіс файлів уже закритий.');
    if (busy) throw StateError('Попередня дія ще триває.');
    busy = true;
    _cancelled = false;
    _report(0, description);
    try {
      return await action();
    } catch (_) {
      if (_cancelled || _disposed) throw const OperationCancelled();
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _protect(String path) async {
    if (Platform.isIOS) {
      await _files.invokeMethod<void>('excludeFromBackup', {'path': path});
    }
  }

  Future<String?> pick({PasswordPrompt? requestPassword}) =>
      _run('Обери файл', () async {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: [
            'gguf',
            'mbtiles',
            'json',
            'geojson',
            'txt',
            'md',
            'amidbackup',
          ],
        );
        if (file == null) return null;
        final length = await file.length();
        if (length == null) {
          throw const FileSystemException('Не вдалося визначити розмір файла.');
        }
        return _importStream(
          file.name,
          length,
          file.readAsByteStream,
          requestPassword: requestPassword,
        );
      });

  Future<String> importPath(String path, {String? name}) async {
    final file = File(path);
    return importStream(
      name ?? p.basename(path),
      await file.length(),
      file.openRead,
    );
  }

  Future<String> importStream(
    String name,
    int length,
    Stream<List<int>> Function() read, {
    PasswordPrompt? requestPassword,
  }) => _run(
    'Готую імпорт',
    () => _importStream(name, length, read, requestPassword: requestPassword),
  );

  Future<String> _importStream(
    String name,
    int length,
    Stream<List<int>> Function() read, {
    PasswordPrompt? requestPassword,
  }) async {
    _checkCancelled();
    final ext = p.extension(name).toLowerCase(),
        binary = {
          '.gguf',
          '.mbtiles',
        }.contains(p.extension(name).toLowerCase());
    if (!{
      '.gguf',
      '.mbtiles',
      '.json',
      '.geojson',
      '.txt',
      '.md',
      '.amidbackup',
    }.contains(ext)) {
      throw const FormatException('Непідтримуваний формат файла.');
    }
    final textLimit = {'.json', '.amidbackup'}.contains(ext)
        ? 48 * 1024 * 1024
        : 32 * 1024 * 1024;
    if (length < 0 || length > (binary ? 8 * 1024 * 1024 * 1024 : textLimit)) {
      throw const FormatException(
        'Ліміт: 8 GiB для моделі / карти, 32 MiB для текстового пакета.',
      );
    }
    if (binary) {
      final id = const Uuid().v4(),
          dir = Directory(p.join(store.backend.directory, 'files'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, '$id$ext')),
          partial = File(p.join(dir.path, '$id$ext.partial'));
      try {
        final sink = partial.openWrite();
        var copied = 0, last = 0;
        try {
          await for (final chunk in _reads.read(read(), _checkCancelled)) {
            _checkCancelled();
            copied += chunk.length;
            if (copied > length) {
              throw const FileSystemException('Розмір файла змінився.');
            }
            sink.add(chunk);
            if (copied - last > 2 * 1024 * 1024) {
              last = copied;
              _report(copied / length * .8, 'Копіюю $name');
              await sink.flush();
            }
          }
        } finally {
          await sink.close();
        }
        if (await partial.length() != length) {
          throw const FileSystemException('Неповна копія файла.');
        }
        _checkCancelled();
        await partial.rename(file.path);
        Json extra = {};
        if (ext == '.gguf') {
          final input = await file.open();
          try {
            if (ascii.decode(await input.read(4), allowInvalid: true) !=
                'GGUF') {
              throw const FormatException('Файл не є GGUF-моделлю.');
            }
          } finally {
            await input.close();
          }
        } else {
          extra = await inspectMap(file.path);
        }
        _report(.86, 'Перевіряю файл');
        final hash = await sha256
            .bind(_reads.read(file.openRead(), _checkCancelled))
            .first;
        _checkCancelled();
        await _protect(file.path);
        await store.addAsset({
          'id': id,
          'title': name,
          'kind': ext == '.gguf' ? 'model' : 'map',
          'path': file.path,
          'bytes': length,
          'count': 1,
          'sha256': hash.toString(),
          'license':
              'Користувацький імпорт; ліцензія визначається джерелом файла.',
          ...extra,
        }, checkActive: _checkCancelled);
        _report(1, 'Збережено');
        return ext == '.gguf'
            ? 'Модель готова до завантаження в помічнику.'
            : 'Офлайн-карту збережено.';
      } catch (_) {
        if (await partial.exists()) await partial.delete();
        if (await file.exists()) await file.delete();
        rethrow;
      }
    }
    _report(.25, 'Читаю матеріали');
    final chunks = BytesBuilder(copy: false);
    var count = 0;
    await for (final chunk in _reads.read(read(), _checkCancelled)) {
      _checkCancelled();
      count += chunk.length;
      if (count > textLimit || count > length) {
        throw const FormatException('Завеликий текстовий файл.');
      }
      chunks.add(chunk);
    }
    if (count != length) {
      throw const FileSystemException('Неповний текстовий файл.');
    }
    final bytes = chunks.takeBytes();
    final raw = decodeDocument(name, bytes);
    if (bytes.length > BackupCodec.maxPlainBytes &&
        !BackupCodec.isEncrypted(raw)) {
      throw const FormatException('Ліміт відкритих текстових даних — 32 MiB.');
    }
    final data = await BackupCodec.unlock(raw, requestPassword);
    _checkCancelled();
    if (data['format'] == 'AMID_OFFGRID_BACKUP') {
      await store.restore(data, checkActive: _checkCancelled);
      return 'Резервну копію об’єднано з даними пристрою.';
    }
    final pack = documentPack(data, name);
    pack['bytes'] = bytes.length;
    pack['sha256'] = sha256.convert(bytes).toString();
    await store.importKnowledge(pack, checkActive: _checkCancelled);
    _report(1, 'Збережено');
    return 'Матеріали додано до довідника.';
  }

  Future<Json> inspectMap(String path) async {
    final archive = await RasterArchive.open(path);
    try {
      return Json.from(archive.info);
    } finally {
      await archive.close();
    }
  }

  Future<String> downloadStarter() => _run('Готую завантаження', () async {
    if (store.packs.any((p) => p['id'] == starterId)) {
      return 'Стартова модель уже збережена.';
    }
    final dir = Directory(p.join(store.backend.directory, 'files'));
    await dir.create(recursive: true);
    final partial = File(p.join(dir.path, 'qwen3-06b-q8.gguf.partial')),
        target = File(p.join(dir.path, 'qwen3-06b-q8.gguf'));
    try {
      var offset = await partial.exists() ? await partial.length() : 0;
      if (offset > modelBytes) {
        await partial.delete();
        offset = 0;
      }
      if (offset < modelBytes) {
        _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
        final request = await _client!.getUrl(Uri.parse(modelUrl));
        if (offset > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        }
        final response = await request.close();
        if (response.statusCode == 200) {
          offset = 0;
        } else if (response.statusCode == 206) {
          final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(
            response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
          );
          if (range == null ||
              int.parse(range[1]!) != offset ||
              int.parse(range[2]!) < offset ||
              int.parse(range[2]!) >= modelBytes ||
              int.parse(range[3]!) != modelBytes) {
            throw const HttpException('Сервер не підтвердив докачування.');
          }
        } else {
          throw HttpException('Сервер відповів: ${response.statusCode}');
        }
        final sink = partial.openWrite(
          mode: offset > 0 ? FileMode.append : FileMode.write,
        );
        var received = offset, last = offset;
        try {
          await for (final chunk in _reads.read(
            response.timeout(const Duration(seconds: 60)),
            _checkCancelled,
          )) {
            if (_cancelled) {
              throw StateError(
                'Завантаження скасовано. Можна продовжити пізніше.',
              );
            }
            received += chunk.length;
            if (received > modelBytes) {
              throw const FormatException(
                'Завантажений файл має інший розмір.',
              );
            }
            sink.add(chunk);
            if (received - last > 2 * 1024 * 1024) {
              last = received;
              await sink.flush();
              _report(
                received / modelBytes * .9,
                'Завантажено ${prettyBytes(received)} із ${prettyBytes(modelBytes)}',
              );
            }
          }
        } finally {
          await sink.close();
        }
      }
      if (await partial.length() != modelBytes) {
        throw const FileSystemException(
          'Файл завантажено не повністю. Натисни завантаження ще раз для продовження.',
        );
      }
      _report(.92, 'Перевіряю контрольну суму');
      final hash = await sha256
          .bind(_reads.read(partial.openRead(), _checkCancelled))
          .first;
      if (hash.toString() != modelHash) {
        await partial.delete();
        throw const FormatException('Контрольна сума моделі не збігається.');
      }
      _checkCancelled();
      await _protect(partial.path);
      _checkCancelled();
      await partial.rename(target.path);
      try {
        await store.addAsset({
          'id': starterId,
          'title': 'Qwen3 0.6B · Q8',
          'kind': 'model',
          'path': target.path,
          'bytes': modelBytes,
          'count': 1,
          'sha256': modelHash,
          'license': 'Qwen Team · Apache-2.0 · https://huggingface.co/Qwen/Qwen3-0.6B-GGUF',
        }, checkActive: _checkCancelled);
      } catch (_) {
        // Retain verified bytes for a retry if activation never committed.
        if (await target.exists()) await target.rename(partial.path);
        rethrow;
      }
      _report(1, 'Модель збережено');
      return 'Модель перевірено. Завантаж її в помічнику.';
    } finally {
      _client?.close(force: true);
      _client = null;
    }
  });

  Future<void> deleteAsset(Json asset) async {
    final path = asset['path'];
    if (path is! String) return;
    final root = p.normalize(p.join(store.backend.directory, 'files'));
    if (!p.isWithin(root, p.normalize(path))) {
      throw const FileSystemException('Файл поза сховищем застосунку.');
    }
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  void cancel() {
    _cancelled = true;
    _reads.cancel();
    _client?.close(force: true);
  }

  Future<void> exportBackup({String? password}) =>
      _run('Готую резервну копію', () async {
        await store.flush();
        final backup = password == null
            ? store.backup()
            : await BackupCodec.encrypt(store.backup(), password);
        _checkCancelled();
        final bytes = utf8.encode(jsonEncode(backup));
        if (password == null && bytes.length > BackupCodec.maxPlainBytes) {
          throw const FormatException(
            'Ліміт текстової резервної копії — 32 MiB.',
          );
        }
        final result = await FilePicker.saveFile(
          fileName: password == null
              ? 'AMID_Offgrid_Backup.json'
              : 'AMID_Offgrid_Backup.amidbackup',
          bytes: Uint8List.fromList(bytes),
          mimeType: 'application/json',
        );
        if (result == null) throw const OperationCancelled();
      });

  Future<void> exportPins() => _run('Готую точки карти', () async {
    final result = await FilePicker.saveFile(
      fileName: 'AMID_Points.geojson',
      mimeType: 'application/geo+json',
      bytes: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'type': 'FeatureCollection',
            'features': store.pins
                .map(
                  (pin) => {
                    'type': 'Feature',
                    'properties': {'name': pin.name, 'id': pin.id},
                    'geometry': {
                      'type': 'Point',
                      'coordinates': [pin.longitude, pin.latitude],
                    },
                  },
                )
                .toList(),
          }),
        ),
      ),
    );
    if (result == null) throw const OperationCancelled();
  });

  Future<void> exportRoute(Json route) =>
      _run('Готую маршрут GeoJSON', () async {
        validateGeoJson(route);
        _checkCancelled();
        final result = await FilePicker.saveFile(
          fileName: 'AMID_Route.geojson',
          mimeType: 'application/geo+json',
          bytes: Uint8List.fromList(utf8.encode(jsonEncode(route))),
        );
        if (result == null) throw const OperationCancelled();
      });

  Future<String>
  clearTemporaryFiles() => _run('Очищаю незавершені файли', () async {
    final directory = Directory(p.join(store.backend.directory, 'files'));
    var bytes = 0;
    if (await directory.exists()) {
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File && entry.path.endsWith('.partial')) {
          _checkCancelled();
          bytes += await entry.length();
          await entry.delete();
        }
      }
    }
    return 'Звільнено ${prettyBytes(bytes)}. Збережені пакети залишилися на пристрої.';
  });
}
