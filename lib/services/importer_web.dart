import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/data.dart';
import 'backup_codec.dart';
import 'document_codec.dart';
import 'store.dart';

class ImportService extends ChangeNotifier {
  ImportService(this.store);
  final AppStore store;
  bool _disposed = false, _cancelled = false, busy = false;
  double progress = 0;
  String label = '';
  static const modelBytes = 639446688;

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

  void _checkCancelled() {
    if (_cancelled || _disposed) throw const OperationCancelled();
  }

  Future<T> _run<T>(String description, Future<T> Function() action) async {
    if (_disposed) throw StateError('Сервіс файлів уже закритий.');
    if (busy) throw StateError('Попередня дія ще триває.');
    busy = true;
    _cancelled = false;
    progress = 0;
    label = description;
    notifyListeners();
    try {
      return await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> pick({
    PasswordPrompt? requestPassword,
  }) => _run('Обери файл', () async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'json', 'geojson', 'amidbackup'],
    );
    if (file == null) return null;
    final size = await file.length();
    if (size == null || size < 0 || size > 48 * 1024 * 1024) {
      throw const FormatException('Завеликий текстовий пакет.');
    }
    final builder = BytesBuilder(copy: false);
    var count = 0;
    await for (final chunk in file.readAsByteStream()) {
      _checkCancelled();
      count += chunk.length;
      if (count > size) throw const FormatException('Розмір файла змінився.');
      builder.add(chunk);
      progress = size == 0 ? 0 : count / size;
      label = 'Читаю ${file.name}';
      notifyListeners();
    }
    if (count != size) throw const FormatException('Неповний текстовий файл.');
    final bytes = builder.takeBytes();
    final raw = decodeDocument(file.name, bytes);
    if (bytes.length > BackupCodec.maxPlainBytes &&
        !BackupCodec.isEncrypted(raw)) {
      throw const FormatException('Ліміт відкритих текстових даних — 32 MiB.');
    }
    final data = await BackupCodec.unlock(raw, requestPassword);
    _checkCancelled();
    if (data['format'] == 'AMID_OFFGRID_BACKUP') {
      await store.restore(data);
      return 'Резервну копію об’єднано з даними пристрою.';
    }
    final pack = documentPack(data, file.name);
    pack['bytes'] = bytes.length;
    pack['sha256'] = sha256.convert(bytes).toString();
    await store.importKnowledge(pack);
    return 'Матеріали збережено.';
  });

  Future<String> downloadStarter() async => throw UnsupportedError(
    'Завантаження моделі та локальний запуск доступні в Android / iPhone.',
  );
  Future<void> deleteAsset(Json asset) async {}
  void cancel() {
    _cancelled = true;
  }

  Future<String> clearTemporaryFiles() async =>
      'Незавершені великі завантаження зберігаються лише у встановленому застосунку.';

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
}
