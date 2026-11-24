import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/data.dart';
import '../models/preferences.dart';
import '../models/starter_content.dart';
import 'backend_native.dart' if (dart.library.js_interop) 'backend_web.dart';

class AppStore extends ChangeNotifier {
  AppStore._(this.backend);
  final PlatformBackend backend;
  List<Article> articles = [];
  List<Json> packs = [];
  List<Pin> pins = [];
  List<Message> messages = [];
  Set<String> favoriteKeys = {};
  String themePreference = 'system';
  double readerScale = 1;
  Set<String> preparation = {};
  bool starterAutoSetup = true;
  int contentRevision = 0;
  static const notesId = 'amid-personal-notes';
  static const starterId = 'amid-mobile-starter';
  static const starterRevision = 3;
  String draft = '', selectedModel = '', selectedMap = '';
  Future<void> _writes = Future.value();
  bool _closed = false;
  Future<void>? _closing;
  static Future<AppStore> open({
    String? seedText,
    PlatformBackend? backend,
  }) async {
    final store = AppStore._(backend ?? await PlatformBackend.open());
    try {
      final saved = await store.backend.load();
      if (saved != null) {
        store._apply(saved);
        final starter = store.packs
            .where((p) => p['id'] == starterId)
            .firstOrNull;
        if (starter != null && starter['bundledRevision'] != starterRevision) {
          final pack = parsePack(
            decodeObject(
              seedText ?? await rootBundle.loadString('assets/starter.json'),
            ),
          );
          if (pack['id'] == starterId) {
            store.packs.removeWhere((p) => p['id'] == starterId);
            store.articles.removeWhere((a) => a.packId == starterId);
            store._insertPack({...pack, 'bundledRevision': starterRevision});
            final keys = store.articles.map((a) => a.key).toSet();
            store.favoriteKeys.removeWhere((key) => !keys.contains(key));
            await store.backend.save(store.snapshot(), reindex: true);
          }
        }
      } else {
        final pack = parsePack(
          decodeObject(
            seedText ?? await rootBundle.loadString('assets/starter.json'),
          ),
        );
        store._insertPack({
          ...pack,
          if (pack['id'] == starterId) 'bundledRevision': starterRevision,
        });
        await store.backend.save(store.snapshot(), reindex: true);
      }
      return store;
    } catch (_) {
      await store.backend.close();
      rethrow;
    }
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
    final articleKeys = articles.map((a) => a.key).toSet();
    favoriteKeys = ((data['favoriteKeys'] as List?) ?? [])
        .whereType<String>()
        .where(articleKeys.contains)
        .toSet();
    themePreference =
        {'system', 'light', 'dark'}.contains(data['themePreference'])
        ? data['themePreference'] as String
        : 'system';
    readerScale = checkedReaderScale(data['readerScale'] ?? 1);
    preparation = checkedPreparation(data['preparation'] ?? <String>[]);
    starterAutoSetup = data['starterAutoSetup'] is bool
        ? data['starterAutoSetup'] as bool
        : true;
  }

  Json snapshot() => {
    'articles': articles.map((a) => a.toJson()).toList(),
    'packs': packs.map((p) => Json.from(p)).toList(),
    'pins': pins.map((p) => p.toJson()).toList(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'draft': draft,
    'selectedModel': selectedModel,
    'selectedMap': selectedMap,
    'favoriteKeys': favoriteKeys.toList(),
    'themePreference': themePreference,
    'readerScale': readerScale,
    'preparation': preparation.toList(),
    'starterAutoSetup': starterAutoSetup,
  };
  Future<void> _mutate(
    void Function() change, {
    bool reindex = false,
    bool libraryChanged = false,
    void Function()? checkActive,
  }) {
    if (_closed) return Future.error(StateError('Сховище вже закрите.'));
    final job = _writes.then((_) async {
      checkActive?.call();
      final previous = snapshot();
      try {
        change();
        _checkLimits();
        await backend.save(snapshot(), reindex: reindex);
      } catch (_) {
        _apply(previous);
        rethrow;
      }
      if (reindex || libraryChanged) contentRevision++;
      notifyListeners();
    });
    _writes = job.catchError((Object _) {});
    return job;
  }

  void _checkLimits() {
    if (packs.length > 500 ||
        articles.length > 25000 ||
        pins.length > 10000 ||
        messages.length > 10000) {
      throw const FormatException(
        'Сховище заповнене. Видали непотрібні матеріали перед імпортом.',
      );
    }
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

  Future<void> importKnowledge(Json pack, {void Function()? checkActive}) =>
      _mutate(() => _insertPack(pack), reindex: true, checkActive: checkActive);
  Future<void> addAsset(Json pack, {void Function()? checkActive}) =>
      _mutate(() {
        if (packs.any((p) => p['id'] == pack['id'])) {
          throw const FormatException('Цей файл уже додано.');
        }
        packs.add(pack);
        if (pack['kind'] == 'model') selectedModel = pack['id'] as String;
        if (pack['kind'] == 'map') selectedMap = pack['id'] as String;
      }, checkActive: checkActive);

  /// Replaces only the official model's metadata after its bytes were verified.
  /// A user's selected custom model remains selected.
  Future<void> installStarterModel(Json pack, {void Function()? checkActive}) =>
      _mutate(() {
        if (pack['id'] != starterModelId || pack['kind'] != 'model') {
          throw const FormatException('Невідомий стартовий пакет.');
        }
        packs = [
          ...packs.where((p) => p['id'] != starterModelId),
          Json.from(pack),
        ];
        starterAutoSetup = true;
        if (selectedModel.isEmpty || selectedModel == starterModelId) {
          selectedModel = starterModelId;
        }
      }, checkActive: checkActive);
  Future<void> savePin(Pin pin) => _mutate(() {
    final valid = Pin.fromJson(pin.toJson());
    pins = [...pins.where((p) => p.id != valid.id), valid];
  });
  Future<void> deletePin(String id) =>
      _mutate(() => pins.removeWhere((p) => p.id == id));
  Future<void> setDraft(String text) =>
      _mutate(() => draft = boundedText(text, 4000));
  Future<void> setThemePreference(String value) => _mutate(() {
    if (!{'system', 'light', 'dark'}.contains(value)) {
      throw const FormatException('Невідома тема.');
    }
    themePreference = value;
  });
  Future<void> setReaderScale(double value) =>
      _mutate(() => readerScale = checkedReaderScale(value));
  Future<void> setPrepared(String id, bool value) => _mutate(() {
    if (!preparationItems.containsKey(id)) {
      throw const FormatException('Невідомий пункт підготовки.');
    }
    value ? preparation.add(id) : preparation.remove(id);
  });
  Future<void> toggleFavorite(String key) => _mutate(() {
    if (!articles.any((a) => a.key == key)) {
      throw const FormatException('Статтю вже видалено.');
    }
    if (!favoriteKeys.remove(key)) favoriteKeys.add(key);
  }, libraryChanged: true);

  Future<void> saveNote({
    String? id,
    required String title,
    required String body,
    String category = 'Мої нотатки',
  }) => _mutate(() {
    final noteId = id ?? const Uuid().v4();
    checkedText(noteId, 'ID нотатки', 100);
    final parsed = parsePack({
      'format': 'AMID_OFFGRID_PACK',
      'version': 1,
      'id': notesId,
      'title': 'Мої нотатки',
      'license': 'Власні матеріали користувача.',
      'articles': [
        {
          'id': noteId,
          'title': title.trim(),
          'body': body,
          'category': category.trim().isEmpty ? 'Мої нотатки' : category.trim(),
        },
      ],
    });
    if (!packs.any((p) => p['id'] == notesId)) {
      _insertPack(parsed);
    } else {
      final note = Article.fromJson(
        Json.from((parsed['articles'] as List).single),
      );
      articles = [...articles.where((a) => a.key != note.key), note];
      packs = packs
          .map(
            (p) => p['id'] == notesId
                ? {
                    ...p,
                    'count': articles.where((a) => a.packId == notesId).length,
                  }
                : p,
          )
          .toList();
    }
  }, reindex: true);

  Future<void> deleteNote(String key) => _mutate(() {
    if (!articles.any((a) => a.key == key && a.packId == notesId)) {
      throw const FormatException('Можна видаляти лише власні нотатки.');
    }
    articles.removeWhere((a) => a.key == key);
    favoriteKeys.remove(key);
    final count = articles.where((a) => a.packId == notesId).length;
    if (count == 0) {
      packs.removeWhere((p) => p['id'] == notesId);
    } else {
      packs = packs
          .map((p) => p['id'] == notesId ? {...p, 'count': count} : p)
          .toList();
    }
  }, reindex: true);
  Future<void> selectModel(String id) => _mutate(() => selectedModel = id);
  Future<void> selectMap(String id) => _mutate(() => selectedMap = id);
  Future<void> saveMessage(Message message) =>
      _mutate(() => _insertMessage(message));

  void _insertMessage(Message message) {
    Message.parse(
      message.toWire(),
      direction: message.direction,
      status: message.status,
    );
    final old = messages.where((m) => m.id == message.id).firstOrNull;
    if (old != null) {
      if (old.body != message.body ||
          old.createdAt != message.createdAt ||
          old.direction != message.direction) {
        throw const FormatException('Конфлікт ID повідомлення.');
      }
      return;
    }
    if (messages.length >= 10000) {
      throw const FormatException('Сховище повідомлень заповнене.');
    }
    messages.add(message);
  }

  Future<Message> saveDraftMessage(String text) async {
    final message = Message(
      const Uuid().v4(),
      text.trim(),
      DateTime.now().toUtc().toIso8601String(),
      'out',
      'draft',
    );
    await _mutate(() {
      _insertMessage(message);
      if (draft == text) draft = '';
    });
    return message;
  }

  Future<void> deleteMessage(String id) =>
      _mutate(() => messages.removeWhere((m) => m.id == id));
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
    if (id == starterModelId) starterAutoSetup = false;
    articles.removeWhere((a) => a.packId == id);
    final articleKeys = articles.map((a) => a.key).toSet();
    favoriteKeys.removeWhere((key) => !articleKeys.contains(key));
    if (selectedModel == id) selectedModel = '';
    if (selectedMap == id) selectedMap = '';
  }, reindex: true);
  Future<List<Article>> search(
    String query, {
    int limit = 80,
    String category = '',
    bool favoritesOnly = false,
  }) async {
    if (_closed) throw StateError('Сховище вже закрите.');
    final maximum = limit.clamp(0, 25000);
    if (maximum == 0) return [];
    bool visible(Article article) =>
        (category.isEmpty || article.category == category) &&
        (!favoritesOnly || favoriteKeys.contains(article.key));
    if (query.trim().isEmpty) {
      final matches = articles.where(visible).toList();
      return [
        ...matches.where((a) => a.packId == notesId).toList().reversed,
        ...matches.where((a) => a.packId != notesId),
      ].take(maximum).toList();
    }
    final words = searchTerms(query);
    if (words.isEmpty) return [];
    // Rank and filter the complete match set, not just SQLite's first 80 rows.
    final keys = (await backend.searchKeys(query, articles.length)).toSet(),
        found = articles
            .where((a) => keys.contains(a.key) && visible(a))
            .toList();
    int rank(Article a) {
      final title = a.title.toLowerCase(), body = a.body.toLowerCase();
      return words.fold(
        0,
        (n, w) => n + (title.contains(w) ? 5 : 0) + (body.contains(w) ? 1 : 0),
      );
    }

    final ranks = {for (final a in found) a.key: rank(a)};
    found.sort((a, b) => ranks[b.key]!.compareTo(ranks[a.key]!));
    return found.take(maximum).toList();
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
            if (p['routing'] != null) 'routing': p['routing'],
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
    'draft': draft,
    'favoriteKeys': favoriteKeys.toList(),
    'themePreference': themePreference,
    'readerScale': readerScale,
    'preparation': preparation.toList(),
  };
  Future<void> restore(Json value, {void Function()? checkActive}) async {
    if (value['format'] != 'AMID_OFFGRID_BACKUP' ||
        value['version'] != 1 ||
        value['packs'] is! List ||
        value['pins'] is! List ||
        value['messages'] is! List) {
      throw const FormatException('Некоректна резервна копія.');
    }
    final incomingPacks = (value['packs'] as List)
            .map((p) => parsePack(checkedObject(p, 'пакет')))
            .toList(),
        incomingPins = (value['pins'] as List)
            .map((p) => Pin.fromJson(checkedObject(p, 'точка')))
            .toList();
    final incomingMessages = (value['messages'] as List).map((m) {
      final data = checkedObject(m, 'повідомлення');
      final direction = data['direction'];
      if (!{'in', 'out'}.contains(direction)) {
        throw const FormatException('Некоректний напрям повідомлення.');
      }
      return Message.parse(
        data,
        direction: direction as String,
        status: direction == 'in' ? 'received' : 'draft',
      );
    }).toList();
    if (incomingPacks.length > 500 ||
        incomingPins.length > 10000 ||
        incomingMessages.length > 10000) {
      throw const FormatException('Завелика резервна копія.');
    }
    final incomingDraft = checkedText(
      value['draft'] ?? '',
      'чернетка',
      4000,
      empty: true,
    );
    final favorites = value['favoriteKeys'] ?? <dynamic>[];
    if (favorites is! List ||
        favorites.length > 25000 ||
        favorites.any((v) => v is! String || v.length > 202)) {
      throw const FormatException('Некоректний список обраного.');
    }
    final theme = value['themePreference'];
    final scale = value.containsKey('readerScale')
        ? checkedReaderScale(value['readerScale'])
        : null;
    final prepared = value.containsKey('preparation')
        ? checkedPreparation(value['preparation'])
        : null;
    if (theme != null && !{'system', 'light', 'dark'}.contains(theme)) {
      throw const FormatException('Некоректна тема резервної копії.');
    }
    void unique(Iterable<String> ids) {
      final values = ids.toList();
      if (values.toSet().length != values.length) {
        throw const FormatException('Резервна копія містить повторювані ID.');
      }
    }

    unique(incomingPacks.map((p) => p['id'] as String));
    unique(incomingPins.map((p) => p.id));
    unique(incomingMessages.map((m) => m.id));
    await _mutate(
      () {
        for (final p in incomingPacks) {
          if (!packs.any((a) => a['id'] == p['id'])) {
            _insertPack(p);
          } else if (p['id'] == notesId) {
            final existingKeys = articles.map((a) => a.key).toSet();
            articles.addAll(
              (p['articles'] as List)
                  .map((a) => Article.fromJson(Json.from(a as Map)))
                  .where((a) => !existingKeys.contains(a.key)),
            );
            packs = packs
                .map(
                  (a) => a['id'] == notesId
                      ? {
                          ...a,
                          'count': articles
                              .where((v) => v.packId == notesId)
                              .length,
                        }
                      : a,
                )
                .toList();
          }
        }
        for (final p in incomingPins) {
          if (!pins.any((a) => a.id == p.id)) pins.add(p);
        }
        for (final m in incomingMessages) {
          final existing = messages.where((a) => a.id == m.id).firstOrNull;
          if (existing == null) {
            messages.add(m);
          } else if (existing.body != m.body ||
              existing.createdAt != m.createdAt ||
              existing.direction != m.direction) {
            throw const FormatException(
              'Конфлікт ID повідомлень у резервній копії.',
            );
          }
        }
        final articleKeys = articles.map((a) => a.key).toSet();
        favoriteKeys.addAll(
          favorites.cast<String>().where(articleKeys.contains),
        );
        if (draft.isEmpty) draft = incomingDraft;
        if (theme != null) themePreference = theme as String;
        if (scale != null) readerScale = scale;
        if (prepared != null) preparation = prepared;
      },
      reindex: true,
      checkActive: checkActive,
    );
  }

  Future<void> flush() => _writes;

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = _writes.then((_) => backend.close());
  }
}
