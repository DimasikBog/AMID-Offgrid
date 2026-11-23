import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/data.dart';
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
    progress = value;
    label = text;
    notifyListeners();
  }

  Future<void> _protect(String path) async {
    if (Platform.isIOS) {
      await _files.invokeMethod<void>('excludeFromBackup', {'path': path});
    }
  }

  Future<String?> pick() async {
    if (busy) throw StateError('Попередня дія ще триває.');
    busy = true;
    _report(0, 'Обери файл');
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['gguf', 'mbtiles', 'json', 'geojson', 'txt', 'md'],
      );
      if (file == null) return null;
      final length = await file.length();
      if (length == null) {
        throw const FileSystemException('Не вдалося визначити розмір файла.');
      }
      return await importStream(file.name, length, file.readAsByteStream);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

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
    Stream<List<int>> Function() read,
  ) async {
    final ext = p.extension(name).toLowerCase(),
        binary = {
          '.gguf',
          '.mbtiles',
        }.contains(p.extension(name).toLowerCase());
    if (length > (binary ? 8 * 1024 * 1024 * 1024 : 32 * 1024 * 1024)) {
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
          await for (final chunk in read()) {
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
        final hash = await sha256.bind(file.openRead()).first;
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
        });
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
    await for (final chunk in read()) {
      count += chunk.length;
      if (count > 32 * 1024 * 1024) {
        throw const FormatException('Завеликий текстовий файл.');
      }
      chunks.add(chunk);
    }
    final bytes = chunks.takeBytes(), text = utf8.decode(bytes);
    Json pack;
    if (ext == '.txt' || ext == '.md') {
      pack = parsePack({
        'format': 'AMID_OFFGRID_PACK',
        'version': 1,
        'id': 'text-${const Uuid().v4()}',
        'title': name,
        'license': 'Власний матеріал користувача.',
        'articles': [
          {'id': 'document', 'title': name, 'body': text},
        ],
      });
    } else {
      final data = decodeObject(text);
      if (data['format'] == 'AMID_OFFGRID_BACKUP') {
        await store.restore(data);
        return 'Резервну копію відновлено.';
      }
      pack = parsePack(
        data['type'] == 'FeatureCollection'
            ? {
                'format': 'AMID_OFFGRID_PACK',
                'version': 1,
                'id': 'map-${const Uuid().v4()}',
                'title': name,
                'license': 'Користувацький GeoJSON.',
                'articles': [],
                'map': data,
              }
            : data,
      );
    }
    pack['bytes'] = bytes.length;
    pack['sha256'] = sha256.convert(bytes).toString();
    await store.importKnowledge(pack);
    _report(1, 'Збережено');
    return 'Матеріали додано до довідника.';
  }

  Future<Json> inspectMap(String path) async {
    final db = await openReadOnlyDatabase(path, singleInstance: false);
    try {
      final rows = await db.query('metadata'),
          metadata = {for (final r in rows) '${r['name']}': '${r['value']}'};
      if (!{
        'png',
        'jpg',
        'jpeg',
        'webp',
      }.contains(metadata['format']?.toLowerCase())) {
        throw const FormatException(
          'Підтримуються растрові MBTiles: PNG, JPG, WebP. Векторні PBF ще не підтримуються.',
        );
      }
      if ((await db.rawQuery(
        'SELECT zoom_level,tile_column,tile_row,tile_data FROM tiles LIMIT 1',
      )).isEmpty) {
        throw const FormatException('Карта не містить тайлів.');
      }
      final center = metadata['center']
              ?.split(',')
              .map(double.tryParse)
              .toList(),
          bounds = metadata['bounds']?.split(',').map(double.tryParse).toList();
      var lat = 20.0, lon = 0.0, zoom = 2.0;
      if (center?.length == 3 &&
          center!.every((v) => v != null && v.isFinite)) {
        lon = center[0]!;
        lat = center[1]!;
        zoom = center[2]!;
      } else if (bounds?.length == 4 &&
          bounds!.every((v) => v != null && v.isFinite)) {
        lon = (bounds[0]! + bounds[2]!) / 2;
        lat = (bounds[1]! + bounds[3]!) / 2;
        zoom = double.tryParse(metadata['minzoom'] ?? '') ?? 5;
      }
      if (lat.abs() > 85 || lon.abs() > 180 || !zoom.isFinite) {
        throw const FormatException('Некоректні межі карти.');
      }
      return {
        'center': [lat, lon, zoom.clamp(0, 20)],
        'minZoom': double.tryParse(metadata['minzoom'] ?? '') ?? 0,
        'maxZoom': double.tryParse(metadata['maxzoom'] ?? '') ?? 20,
        'attribution':
            metadata['attribution'] ?? 'Користувацька карта · перевір джерело',
      };
    } finally {
      await db.close();
    }
  }

  Future<String> downloadStarter() async {
    if (busy) throw StateError('Попередня дія ще триває.');
    if (store.packs.any((p) => p['id'] == starterId)) {
      return 'Стартова модель уже збережена.';
    }
    busy = true;
    _cancelled = false;
    _report(0, 'Готую завантаження');
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
          if (!((response.headers.value(HttpHeaders.contentRangeHeader) ?? '')
              .startsWith('bytes $offset-'))) {
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
          await for (final chunk in response.timeout(
            const Duration(seconds: 60),
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
      final hash = await sha256.bind(partial.openRead()).first;
      if (hash.toString() != modelHash) {
        await partial.delete();
        throw const FormatException('Контрольна сума моделі не збігається.');
      }
      if (_cancelled) throw StateError('Завантаження скасовано.');
      await partial.rename(target.path);
      await _protect(target.path);
      await store.addAsset({
        'id': starterId,
        'title': 'Qwen3 0.6B · Q8',
        'kind': 'model',
        'path': target.path,
        'bytes': modelBytes,
        'count': 1,
        'sha256': modelHash,
        'license': 'Qwen Team · Apache-2.0 · https://huggingface.co/Qwen/Qwen3-0.6B-GGUF',
      });
      _report(1, 'Модель збережено');
      return 'Модель перевірено. Завантаж її в помічнику.';
    } finally {
      _client?.close(force: true);
      _client = null;
      busy = false;
      notifyListeners();
    }
  }

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
    _client?.close(force: true);
  }

  Future<void> exportBackup() async {
    final result = await FilePicker.saveFile(
      fileName: 'AMID_Offgrid_Backup.json',
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(store.backup()))),
      mimeType: 'application/json',
    );
    if (result == null) throw StateError('Збереження скасовано.');
  }
}
