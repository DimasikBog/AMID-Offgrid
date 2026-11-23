import 'package:flutter/foundation.dart';

import '../models/data.dart';
import 'store.dart';

class AssistantService extends ChangeNotifier {
  AssistantService(this.store);
  final AppStore store;
  String? loadedId, error;
  String answer = '', question = '';
  List<Article> sources = [];
  bool loading = false, generating = false, generated = false;
  Duration elapsed = Duration.zero;
  bool get ready => false;
  Future<void> load(Json model) async {
    throw UnsupportedError(
      'Локальна GGUF-модель працює у встановленому Android/iPhone-застосунку.',
    );
  }

  Future<void> ask(String value) async {
    if (value.trim().isEmpty) return;
    question = value.trim();
    answer = '';
    error = null;
    generated = false;
    sources = (await store.search(question, limit: 30)).take(3).toList();
    notifyListeners();
  }

  Future<void> cancel() async {}
  Future<void> unload() async {}
}
