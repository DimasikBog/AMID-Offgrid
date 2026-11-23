import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/data.dart';

class PlatformBackend {
  PlatformBackend._(this.preferences);
  final SharedPreferences preferences;
  Json? _data;
  final directory = '';
  static Future<PlatformBackend> open() async =>
      PlatformBackend._(await SharedPreferences.getInstance());
  Future<Json?> load() async {
    final text = preferences.getString('amid-mobile-state');
    _data = text == null ? null : decodeObject(text);
    return _data;
  }

  Future<void> save(Json data, {bool reindex = false}) async {
    if (!await preferences.setString('amid-mobile-state', jsonEncode(data))) {
      throw StateError('Не вдалося зберегти дані.');
    }
    _data = data;
  }

  Future<List<String>> searchKeys(String query, int limit) async {
    final words = searchTerms(query);
    return ((_data?['articles'] as List?) ?? [])
        .where(
          (a) => words.any(
            (w) => '${a['title']} ${a['body']}'.toLowerCase().contains(w),
          ),
        )
        .take(limit)
        .map((a) => a['key'] as String)
        .toList();
  }

  Future<void> close() async {}
}
