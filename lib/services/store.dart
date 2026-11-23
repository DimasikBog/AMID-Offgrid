import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/data.dart';
import 'backend_native.dart' if (dart.library.js_interop) 'backend_web.dart';

class AppStore extends ChangeNotifier {
  AppStore._(this.backend);
  final PlatformBackend backend;
  List<Article> articles = [];
  List<Json> packs = [];
  List<Pin> pins = [];
  List<Message> messages = [];
  String draft = '', selectedModel = '', selectedMap = '';
  Future<void> _writes = Future.value();
  static Future<AppStore> open({
    String? seedText,
    PlatformBackend? backend,
  }) async {
    final store = AppStore._(backend ?? await PlatformBackend.open());
    final saved = await store.backend.load();
    if (saved != null) {
      store._apply(saved);
    } else {
      final pack = parsePack(
        decodeObject(
          seedText ?? await rootBundle.loadString('assets/starter.json'),
        ),
      );
      store._insertPack(pack);
      await store.backend.save(store.snapshot(), reindex: true);
    }
    return store;
  }

  void _apply(Json data) {
    articles = (data['articles'] as List)
        .map((a) => Article.fromJson(Json.from(a as Map)))
        .toList();
    packs = (data['packs'] as List).map((p) => Json.from(p as Map)).toList();
    pins = (data['pins'] as List)
        .map((p) => Pin.fromJson(Json.from(p as Map)))
        .toList();
    messages = (data['messages'] as List)
        .map((m) => Message.fromJson(Json.from(m as Map)))
        .toList();
    draft = data['draft'] as String? ?? '';
    selectedModel = data['selectedModel'] as String? ?? '';
    selectedMap = data['selectedMap'] as String? ?? '';
  }

  Json snapshot() => {
    'articles': articles.map((a) => a.toJson()).toList(),
    'packs': packs.map((p) => Json.from(p)).toList(),
    'pins': pins.map((p) => p.toJson()).toList(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'draft': draft,
    'selectedModel': selectedModel,
    'selectedMap': selectedMap,
  };
  Future<void> _mutate(void Function() change, {bool reindex = false}) {
    final job = _writes.then((_) async {
      final previous = snapshot();
      try {
        change();
        await backend.save(snapshot(), reindex: reindex);
      } catch (_) {
        _apply(previous);
        rethrow;
      }
      notifyListeners();
    });
    _writes = job.catchError((Object _) {});
    return job;
  }

  void _insertPack(Json pack) {
    if (packs.any((p) => p['id'] == pack['id'])) {
      throw const FormatException('Пакет із цим ID вже є на пристрої.');
    }
    articles.addAll(
      (pack['articles'] as List).map(
        (a) => Article.fromJson(Json.from(a as Map)),
      ),
    );
    final metadata = Json.from(pack)..remove('articles');
    metadata['count'] = (pack['articles'] as List).length;
    metadata['bytes'] ??= 0;
    packs.add(metadata);
  }

  Future<void> importKnowledge(Json pack) =>
      _mutate(() => _insertPack(pack), reindex: true);
  Future<void> addAsset(Json pack) => _mutate(() {
    if (packs.any((p) => p['id'] == pack['id'])) {
      throw const FormatException('Цей файл уже додано.');
    }
    packs.add(pack);
    if (pack['kind'] == 'model') selectedModel = pack['id'] as String;
    if (pack['kind'] == 'map') selectedMap = pack['id'] as String;
  });
  Future<void> savePin(Pin pin) =>
      _mutate(() => pins = [...pins.where((p) => p.id != pin.id), pin]);
  Future<void> deletePin(String id) =>
      _mutate(() => pins.removeWhere((p) => p.id == id));
  Future<void> setDraft(String text) => _mutate(
    () => draft = text.length <= 4000 ? text : text.substring(0, 4000),
  );
  Future<void> selectModel(String id) => _mutate(() => selectedModel = id);
  Future<void> selectMap(String id) => _mutate(() => selectedMap = id);
  Future<void> saveMessage(Message message) => _mutate(() {
    final old = messages.where((m) => m.id == message.id).firstOrNull;
    if (old != null) {
      if (old.body != message.body || old.createdAt != message.createdAt) {
        throw const FormatException('Конфлікт ID повідомлення.');
      }
      return;
    }
    if (messages.length >= 10000) {
      throw const FormatException('Сховище повідомлень заповнене.');
    }
    messages.add(message);
  });
  Future<void> messageStatus(String id, String status) => _mutate(
    () => messages = messages
        .map(
          (m) =>
              m.id == id &&
                  m.direction == 'out' &&
                  !(m.status == 'delivered' && status == 'transferred')
              ? m.withStatus(status)
              : m,
        )
        .toList(),
  );
  Future<void> removePack(String id) => _mutate(() {
    if (id == 'amid-mobile-starter') {
      throw const FormatException('Стартовий набір входить до застосунку.');
    }
    packs.removeWhere((p) => p['id'] == id);
    articles.removeWhere((a) => a.packId == id);
    if (selectedModel == id) selectedModel = '';
    if (selectedMap == id) selectedMap = '';
  }, reindex: true);
  Future<List<Article>> search(String query, {int limit = 80}) async {
    if (query.trim().isEmpty) return articles.take(limit).toList();
    final words = searchTerms(query);
    if (words.isEmpty) return [];
    final keys = (await backend.searchKeys(query, limit)).toSet(),
        found = articles.where((a) => keys.contains(a.key)).toList();
    int rank(Article a) => words.fold(
      0,
      (n, w) =>
          n +
          (a.title.toLowerCase().contains(w) ? 5 : 0) +
          (a.body.toLowerCase().contains(w) ? 1 : 0),
    );
    found.sort((a, b) => rank(b).compareTo(rank(a)));
    return found;
  }

  Json backup() => {
    'format': 'AMID_OFFGRID_BACKUP',
    'version': 1,
    'packs': packs
        .where(
          (p) => p['kind'] == 'knowledge' && p['id'] != 'amid-mobile-starter',
        )
        .map(
          (p) => {
            'format': 'AMID_OFFGRID_PACK',
            'version': 1,
            'id': p['id'],
            'title': p['title'],
            'license': p['license'],
            if (p['map'] != null) 'map': p['map'],
            'articles': articles
                .where((a) => a.packId == p['id'])
                .map(
                  (a) => {
                    'id': a.key.substring(a.packId.length + 2),
                    'title': a.title,
                    'body': a.body,
                    'category': a.category,
                    'source': a.source,
                  },
                )
                .toList(),
          },
        )
        .toList(),
    'pins': pins.map((p) => p.toJson()).toList(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };
  Future<void> restore(Json value) async {
    if (value['format'] != 'AMID_OFFGRID_BACKUP' ||
        value['version'] != 1 ||
        value['packs'] is! List ||
        value['pins'] is! List ||
        value['messages'] is! List) {
      throw const FormatException('Некоректна резервна копія.');
    }
    final incomingPacks = (value['packs'] as List)
            .map((p) => parsePack(Json.from(p as Map)))
            .toList(),
        incomingPins = (value['pins'] as List)
            .map((p) => Pin.fromJson(Json.from(p as Map)))
            .toList();
    final incomingMessages = (value['messages'] as List)
        .map(
          (m) => Message.parse(
            Json.from(m as Map),
            direction: m['direction'] == 'in' ? 'in' : 'out',
            status: m['direction'] == 'in' ? 'received' : 'draft',
          ),
        )
        .toList();
    if (incomingPacks.length > 500 ||
        incomingPins.length > 10000 ||
        incomingMessages.length > 10000) {
      throw const FormatException('Завелика резервна копія.');
    }
    await _mutate(() {
      for (final p in incomingPacks) {
        if (!packs.any((a) => a['id'] == p['id'])) _insertPack(p);
      }
      for (final p in incomingPins) {
        if (!pins.any((a) => a.id == p.id)) pins.add(p);
      }
      for (final m in incomingMessages) {
        if (!messages.any((a) => a.id == m.id)) messages.add(m);
      }
    }, reindex: true);
  }

  Future<void> close() => backend.close();
}
