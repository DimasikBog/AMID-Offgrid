import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class AtlasStorage {
  AtlasStorage(this.root, {this.scope = 'atlas'}) {
    if (!{'atlas', 'streets'}.contains(scope)) {
      throw ArgumentError('Unknown map storage scope');
    }
  }
  final String root;
  final String scope;
  File _file(String id) {
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,79}$').hasMatch(id)) {
      throw const FormatException('Некоректний ID карти.');
    }
    return File(p.join(root, scope, '$id.${scope == 'atlas' ? 'jpg' : 'bin'}'));
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

  Future<void> prune(Set<String> keep) async {
    if (scope != 'streets') {
      throw StateError('Only street storage can be pruned.');
    }
    final directory = Directory(p.join(root, scope));
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          !keep.contains(p.basenameWithoutExtension(entity.path))) {
        await entity.delete();
      }
    }
  }
}
