import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _initialized = false;

DatabaseFactory get nativeDatabaseFactory {
  if (Platform.isWindows || Platform.isLinux) {
    if (!_initialized) {
      sqfliteFfiInit();
      _initialized = true;
    }
    return databaseFactoryFfi;
  }
  return databaseFactory;
}
