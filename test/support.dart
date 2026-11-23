import 'dart:io';

import 'package:amid_offgrid/services/backend_native.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<({Directory root, AppStore store})> openTestStore() async {
  sqfliteFfiInit();
  final root = await Directory.systemTemp.createTemp('amid-completion-');
  final store = await AppStore.open(
    backend: await PlatformBackend.open(
      factory: databaseFactoryFfi,
      root: root,
    ),
    seedText: File('assets/starter.json').readAsStringSync(),
  );
  return (root: root, store: store);
}
