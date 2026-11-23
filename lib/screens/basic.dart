import 'dart:async';

import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/services.dart';
import '../services/store.dart';
import '../widgets/common.dart';
import 'note_editor.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.services,
    required this.navigate,
    required this.openPacks,
  });
  final Services services;
  final void Function(int) navigate;
  final VoidCallback openPacks;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.store,
      services.assistant,
      services.nearby,
    ]),
    builder: (context, _) {
      final data = services.store;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Panel(
            color: const Color(0xff254231),
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ТВІЙ ПРОСТІР AMID',
                  style: TextStyle(color: mint, fontSize: 12, letterSpacing: 2),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Твій світ.\nБез мережі.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    height: 1.06,
                    letterSpacing: -1.8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Знання, локальний ШІ, карти\nта зв’язок у твоїй кишені.',
                  style: TextStyle(color: Color(0xffcadcc9), height: 1.6),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: openPacks,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Мій офлайн-набір'),
                ),
              ],
            ),
          ),
          const Section('Все потрібне поруч'),
          LayoutBuilder(
            builder: (context, c) => GridView.count(
              crossAxisCount: c.maxWidth > 650 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio:
                  (c.maxWidth > 650 ? 1.15 : 1.03) /
                  (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
                    1,
                    2.5,
                  ),
              children: [
                _Module(
                  'Довідник',
                  '${data.articles.length} статей',
                  Icons.menu_book_rounded,
                  () => navigate(1),
                ),
                _Module(
                  'Помічник',
                  services.assistant.ready
                      ? 'Модель завантажена'
                      : 'Запитай про свої матеріали',
                  Icons.auto_awesome_rounded,
                  () => navigate(2),
                ),
                _Module(
                  'Карта',
                  '${data.pins.length} власних точок',
                  Icons.map_outlined,
                  () => navigate(3),
                ),
                _Module(
                  'Зв’язок',
                  services.nearby.connected
                      ? 'Телефони з’єднані'
                      : 'Поруч, навіть без мережі',
                  Icons.forum_outlined,
                  () => navigate(4),
                ),
              ],
            ),
          ),
          Section(
            'Підготуйся заздалегідь',
            action: IconButton(
              tooltip: 'Відкрити пакети',
              onPressed: openPacks,
              icon: const Icon(Icons.inventory_2_outlined),
            ),
          ),
          Panel(
            child: Column(
              children: [
                _ReadyRow(
                  'Довідник на пристрої',
                  'Відкривається без мережі',
                  data.articles.isNotEmpty,
                ),
                _ReadyRow('Карти', 'Оглядова карта світу вже всередині', true),
                _ReadyRow(
                  'Локальний ШІ',
                  data.packs.any((p) => p['kind'] == 'model')
                      ? 'Модель збережена на пристрої'
                      : 'Додай GGUF-модель у «Пакетах»',
                  data.packs.any((p) => p['kind'] == 'model'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: openPacks,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Додати свої матеріали'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Без облікового запису. Твої дані зберігаються на цьому пристрої.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}

class _Module extends StatelessWidget {
  const _Module(this.title, this.subtitle, this.icon, this.onTap);
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReadyRow extends StatelessWidget {
  const _ReadyRow(this.title, this.body, this.ready);
  final String title, body;
  final bool ready;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      ready
          ? Icons.check_circle_outline_rounded
          : Icons.add_circle_outline_rounded,
      color: ready
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.outline,
    ),
    title: Text(title),
    subtitle: Text(body),
  );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.services,
    required this.navigate,
  });
  final Services services;
  final void Function(int) navigate;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _term = '', _category = '';
  bool _favorites = false;
  int _limit = 40, _revision = 0;
  late Future<List<Article>> _results;
  @override
  void initState() {
    super.initState();
    _revision = widget.services.store.contentRevision;
    _search();
  }

  void _search() {
    _results = widget.services.store.search(
      _term,
      limit: _limit + 1,
      category: _category,
      favoritesOnly: _favorites,
    );
  }

  void _refresh() {
    _debounce?.cancel();
    setState(() {
      _limit = 40;
      _search();
    });
  }

  @override
  void didUpdateWidget(covariant LibraryScreen old) {
    super.didUpdateWidget(old);
    final store = widget.services.store;
    if (_revision != store.contentRevision) {
      _revision = store.contentRevision;
      if (!store.articles.any((a) => a.category == _category)) _category = '';
      _search();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.services.store;
    final categories = store.articles.map((a) => a.category).toSet().toList()
      ..sort();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    hintText: 'Пошук у твоїх матеріалах',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Знайти',
                      onPressed: _refresh,
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ),
                  onChanged: (value) {
                    _term = value;
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      if (mounted) _refresh();
                    });
                  },
                  onSubmitted: (_) => _refresh(),
                ),
              ),
              IconButton(
                tooltip: 'Створити нотатку',
                icon: const Icon(Icons.note_add_outlined),
                onPressed: () => editNote(context, store),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: _category,
                  isExpanded: true,
                  hint: const Text('Категорія'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Усі категорії'),
                    ),
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category,
                        child: Text(category, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    _category = value ?? '';
                    _refresh();
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Обране'),
                selected: _favorites,
                onSelected: (value) {
                  _favorites = value;
                  _refresh();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Article>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyState('Пошук недоступний', '${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final articles = snapshot.data!;
              if (articles.isEmpty) {
                return EmptyState(
                  _favorites
                      ? 'В обраному поки порожньо'
                      : 'Нічого не знайдено',
                  _favorites
                      ? 'Натисни зірочку біля потрібної статті.'
                      : 'Спробуй інше слово або додай власні матеріали.',
                  icon: _favorites
                      ? Icons.star_outline_rounded
                      : Icons.search_off_rounded,
                );
              }
              final more = articles.length > _limit;
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
                itemCount: more ? _limit + 1 : articles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (more && i == _limit) {
                    return OutlinedButton(
                      onPressed: () => setState(() {
                        _limit += 40;
                        _search();
                      }),
                      child: const Text('Показати ще'),
                    );
                  }
                  final a = articles[i],
                      favorite = store.favoriteKeys.contains(articles[i].key);
                  return Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      leading: Icon(
                        a.packId == AppStore.notesId
                            ? Icons.edit_note_rounded
                            : Icons.article_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        a.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(a.category),
                      ),
                      trailing: IconButton(
                        tooltip: favorite
                            ? 'Прибрати з обраного'
                            : 'Додати до обраного',
                        onPressed: () =>
                            guarded(context, () => store.toggleFavorite(a.key)),
                        icon: Icon(
                          favorite
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                        ),
                      ),
                      onTap: () => openArticle(
                        context,
                        a,
                        widget.services,
                        widget.navigate,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

void openArticle(
  BuildContext context,
  Article article,
  Services services,
  void Function(int) navigate,
) {
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _ArticleScreen(
        articleKey: article.key,
        services: services,
        navigate: navigate,
      ),
    ),
  );
}

class _ArticleScreen extends StatelessWidget {
  const _ArticleScreen({
    required this.articleKey,
    required this.services,
    required this.navigate,
  });
  final String articleKey;
  final Services services;
  final void Function(int) navigate;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.store,
    builder: (context, _) {
      final store = services.store;
      final article = store.articles
          .where((a) => a.key == articleKey)
          .firstOrNull;
      if (article == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Довідник')),
          body: const EmptyState(
            'Статтю видалено',
            'Повернися до списку матеріалів.',
          ),
        );
      }
      final favorite = store.favoriteKeys.contains(article.key);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Довідник'),
          actions: [
            IconButton(
              tooltip: favorite ? 'Прибрати з обраного' : 'Додати до обраного',
              onPressed: () =>
                  guarded(context, () => store.toggleFavorite(article.key)),
              icon: Icon(
                favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              ),
            ),
            if (article.packId == AppStore.notesId)
              IconButton(
                tooltip: 'Редагувати нотатку',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => editNote(context, store, article: article),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 40),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Pill(article.category),
            ),
            const SizedBox(height: 20),
            Text(
              article.title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 22),
            SelectableText(
              article.body,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(height: 1.8),
            ),
            const SizedBox(height: 25),
            Text(article.license, style: Theme.of(context).textTheme.bodySmall),
            if (article.source.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText(
                  'Джерело: ${article.source}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 25),
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Запитати про статтю'),
              onPressed: () {
                Navigator.pop(context);
                navigate(2);
                unawaitedAsk(services, article.title);
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Додати до повідомлення'),
              onPressed: () => guarded(context, () async {
                await store.setDraft(
                  '${article.title}\n\n${article.body}\n\n${article.license}',
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  navigate(4);
                }
              }),
            ),
            if (article.packId == AppStore.notesId) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Видалити нотатку'),
                onPressed: () => guarded(context, () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Видалити нотатку?'),
                      content: Text(article.title),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Залишити'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Видалити'),
                        ),
                      ],
                    ),
                  );
                  if (yes != true) return;
                  await store.deleteNote(article.key);
                  if (context.mounted) Navigator.pop(context);
                }),
              ),
            ],
          ],
        ),
      );
    },
  );
}

void unawaitedAsk(Services s, String question) {
  unawaited(s.assistant.ask(question));
}
