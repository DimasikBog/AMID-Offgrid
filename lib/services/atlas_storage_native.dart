import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class AtlasStorage {
  AtlasStorage(this.root);
  final String root;
  File _file(String id) {
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,79}$').hasMatch(id)) {
      throw const FormatException('Некоректний ID карти.');
    }
    return File(p.join(root, 'atlas', '$id.jpg'));
  }

  Future<void> put(String id, Uint8List bytes) async {
    final file = _file(id);
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.partial');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
  }

  Future<Uint8List?> read(String id) async {
    final file = _file(id);
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> delete(String id) async {
    final file = _file(id);
    if (await file.exists()) await file.delete();
  }

  void dispose() {}
}
