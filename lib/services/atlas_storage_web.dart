import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

class AtlasStorage {
  AtlasStorage(String root, {this.scope = 'atlas'}) {
    if (!{'atlas', 'streets'}.contains(scope)) {
      throw ArgumentError('Unknown map storage scope');
    }
  }
  final String scope;
  Future<Database>? _opening;
  Future<Database> get _database => _opening ??= idbFactoryWeb.open(
    'amid-offgrid-$scope',
    version: 1,
    onUpgradeNeeded: (event) {
      if (event.oldVersion < 1) event.database.createObjectStore('images');
    },
  );
  void _check(String id) {
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,79}$').hasMatch(id)) {
      throw const FormatException('Некоректний ID карти.');
    }
  }

  Future<void> put(String id, Uint8List bytes) async {
    _check(id);
    final db = await _database;
    final tx = db.transaction('images', idbModeReadWrite);
    await tx.objectStore('images').put(bytes, id);
    await tx.completed;
  }

  Future<Uint8List?> read(String id) async {
    _check(id);
    final db = await _database;
    final tx = db.transaction('images', idbModeReadOnly);
    final value = await tx.objectStore('images').getObject(id);
    await tx.completed;
    return value == null
        ? null
        : Uint8List.fromList((value as List).cast<int>());
  }

  Future<void> delete(String id) async {
    _check(id);
    final db = await _database;
    final tx = db.transaction('images', idbModeReadWrite);
    await tx.objectStore('images').delete(id);
    await tx.completed;
  }

  void dispose() {
    final opening = _opening;
    if (opening != null) {
      opening.then((db) => db.close(), onError: (Object _) {});
    }
  }

  Future<void> prune(Set<String> keep) async {
    if (scope != 'streets') {
      throw StateError('Only street storage can be pruned.');
    }
    final db = await _database;
    final tx = db.transaction('images', idbModeReadWrite);
    final keys = await tx.objectStore('images').getAllKeys();
    for (final key in keys) {
      if (!keep.contains(key)) await tx.objectStore('images').delete(key);
    }
    await tx.completed;
  }
}
