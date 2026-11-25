import 'dart:async';

import 'package:flutter/material.dart';

import '../services/store.dart';
import '../widgets/common.dart';

class SavedPagesScreen extends StatefulWidget {
  const SavedPagesScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<SavedPagesScreen> createState() => _SavedPagesScreenState();
}

class _SavedPagesScreenState extends State<SavedPagesScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  Set<String> _matchedKeys = {};
  int _generation = 0;
  bool _searching = false, _favoritesOnly = false, _alphabetical = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    widget.store.removeListener(_changed);
    _query.dispose();
    super.dispose();
  }

  void _changed() {
    if (_query.text.trim().isNotEmpty) {
      _scheduleSearch();
    } else {
      setState(() {});
    }
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _query.text.trim();
    setState(() {
      _error = null;
      _matchedKeys = {};
      _searching = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        // Search the complete FTS set before limiting to the saved collection.
        final results = await widget.store.search(query, limit: 25000);
        if (!mounted || generation != _generation) return;
        final lower = query.toLowerCase();
        setState(() {
          _matchedKeys = {
            ...results
                .where((a) => a.packId == AppStore.webPagesId)
                .map((a) => a.key),
            ...widget.store.articles
                .where(
                  (a) =>
                      a.packId == AppStore.webPagesId &&
                      (a.title.toLowerCase().contains(lower) ||
                          a.source.toLowerCase().contains(lower)),
                )
                .map((a) => a.key),
          };
          _searching = false;
        });
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(() {
            _searching = false;
            _error = 'Не вдалося виконати пошук. Спробуй ще раз.';
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.store.articles
        .where((a) => a.packId == AppStore.webPagesId)
        .toList()
        .reversed
        .toList();
    final pages = all
        .where(
          (a) =>
              (_query.text.trim().isEmpty || _matchedKeys.contains(a.key)) &&
              (!_favoritesOnly || widget.store.favoriteKeys.contains(a.key)),
        )
        .toList();
    if (_alphabetical) {
      pages.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Збережені сторінки',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      key: const ValueKey('saved-pages-search'),
                      controller: _query,
                      onChanged: (_) => _scheduleSearch(),
                      decoration: InputDecoration(
                        labelText: 'Пошук у збережених текстах',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Очистити пошук',
                                onPressed: () {
                                  _query.clear();
                                  _scheduleSearch();
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilterChip(
                          label: const Text('Лише обране'),
                          selected: _favoritesOnly,
                          onSelected: (value) =>
                              setState(() => _favoritesOnly = value),
                        ),
                        PopupMenuButton<bool>(
                          tooltip: 'Порядок сторінок',
                          initialValue: _alphabetical,
                          onSelected: (value) =>
                              setState(() => _alphabetical = value),
                          icon: const Icon(Icons.sort_by_alpha),
                          itemBuilder: (_) => [
                            CheckedPopupMenuItem(
                              checked: !_alphabetical,
                              value: false,
                              child: const Text('Останні збережені'),
                            ),
                            CheckedPopupMenuItem(
                              checked: _alphabetical,
                              value: true,
                              child: const Text('За назвою'),
                            ),
                          ],
                        ),
                        Text('${pages.length} / ${all.length}'),
                      ],
                    ),
                  ),
                  if (_searching) const LinearProgressIndicator(),
                ],
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: EmptyState(
                  'Помилка пошуку',
                  _error!,
                  action: TextButton(
                    onPressed: _scheduleSearch,
                    child: const Text('Повторити'),
                  ),
                ),
              )
            else if (pages.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  _searching
                      ? 'Шукаю на пристрої…'
                      : all.isEmpty
                      ? 'Поки немає збережених сторінок'
                      : 'Нічого не знайдено',
                  all.isEmpty
                      ? 'Відкрий сайт у режимі читання й натисни «Зберегти офлайн».'
                      : 'Зміни запит або вимкни фільтр обраного. Пошук працює без інтернету.',
                ),
              )
            else
              SliverList.builder(
                itemCount: pages.length,
                itemBuilder: (context, i) {
                  final page = pages[i];
                  final favorite = widget.store.favoriteKeys.contains(page.key);
                  return ListTile(
                    key: ValueKey(page.key),
                    title: Text(page.title),
                    subtitle: Text(
                      page.source,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(context, page),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: favorite
                              ? 'Прибрати сторінку з обраного'
                              : 'Додати сторінку в обране',
                          onPressed: () => guarded(
                            context,
                            () => widget.store.toggleFavorite(page.key),
                          ),
                          icon: Icon(
                            favorite ? Icons.bookmark : Icons.bookmark_border,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Видалити збережену сторінку',
                          onPressed: () => guarded(
                            context,
                            () => widget.store.deleteWebPage(page.key),
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
