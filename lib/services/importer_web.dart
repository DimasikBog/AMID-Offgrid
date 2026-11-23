import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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
  bool busy = false;
  double progress = 0;
  String label = '';
  static const modelBytes = 639446688;
  Future<String?> pick() async {
    if (busy) return null;
    busy = true;
    notifyListeners();
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'json', 'geojson'],
      );
      if (file == null) return null;
      final size = await file.length();
      if (size == null || size > 32 * 1024 * 1024) {
        throw const FormatException('Ліміт текстового пакета: 32 MiB.');
      }
      final text = utf8.decode(await file.readAsBytes());
      Json pack;
      if ({'txt', 'md'}.contains(file.extension)) {
        pack = parsePack({
          'format': 'AMID_OFFGRID_PACK',
          'version': 1,
          'id': 'text-${const Uuid().v4()}',
          'title': file.name,
          'license': 'Власний матеріал користувача.',
          'articles': [
            {'id': 'text', 'title': file.name, 'body': text},
          ],
        });
      } else {
        final data = decodeObject(text);
        if (data['format'] == 'AMID_OFFGRID_BACKUP') {
          await store.restore(data);
          return 'Копію відновлено.';
        }
        pack = parsePack(
          data['type'] == 'FeatureCollection'
              ? {
                  'format': 'AMID_OFFGRID_PACK',
                  'version': 1,
                  'id': 'geo-${const Uuid().v4()}',
                  'title': file.name,
                  'license': 'Користувацький GeoJSON.',
                  'articles': [],
                  'map': data,
                }
              : data,
        );
      }
      await store.importKnowledge(pack);
      return 'Матеріали збережено.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String> downloadStarter() async => throw UnsupportedError(
    'Завантаження моделі та локальний запуск доступні в Android / iPhone.',
  );
  Future<void> deleteAsset(Json asset) async {}
  void cancel() {}
  Future<void> exportBackup() async {
    final result = await FilePicker.saveFile(
      fileName: 'AMID_Offgrid_Backup.json',
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(store.backup()))),
      mimeType: 'application/json',
    );
    if (result == null) throw StateError('Збереження скасовано.');
  }
}
