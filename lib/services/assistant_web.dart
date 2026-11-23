import 'package:flutter/foundation.dart';

import '../models/data.dart';
import 'store.dart';

class AssistantService extends ChangeNotifier {
  AssistantService(
    this.store, {
    Future<List<Article>> Function(String)? findSources,
  }) : _findSources =
           findSources ?? ((query) => store.search(query, limit: 30));
  final AppStore store;
  final Future<List<Article>> Function(String) _findSources;
  String? loadedId, error;
  String answer = '', question = '';
  List<Article> sources = [];
  bool loading = false,
      generating = false,
      generated = false,
      searching = false;
  bool _disposed = false;
  int _request = 0;
  Duration elapsed = Duration.zero;
  bool get ready => false;
  bool get busy => searching || loading || generating;
  Future<void> load(Json model) async {
    throw UnsupportedError(
      'Локальна GGUF-модель працює у встановленому Android/iPhone-застосунку.',
    );
  }

  Future<void> ask(String value) async {
    if (_disposed || busy || value.trim().isEmpty) return;
    final request = ++_request;
    searching = true;
    question = boundedText(value.trim(), 2000);
    answer = '';
    error = null;
    generated = false;
    sources = [];
    notifyListeners();
    try {
      final found = await _findSources(question);
      if (!_disposed && request == _request) sources = found.take(3).toList();
    } catch (e) {
      if (!_disposed && request == _request) {
        error = 'Не вдалося виконати запит: $e';
      }
    } finally {
      if (!_disposed && request == _request) {
        searching = false;
        notifyListeners();
      }
    }
  }

  Future<void> cancel() async {
    _request++;
    searching = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> unload() => cancel();
  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
