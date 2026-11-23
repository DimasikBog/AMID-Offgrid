import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/services.dart';
import '../widgets/common.dart';

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
  String _term = '';
  late Future<List<Article>> _results;
  int _count = 0;
  @override
  void initState() {
    super.initState();
    _count = widget.services.store.articles.length;
    _search();
  }

  void _search() {
    _results = widget.services.store.search(_term);
  }

  @override
  void didUpdateWidget(covariant LibraryScreen old) {
    super.didUpdateWidget(old);
    if (_count != widget.services.store.articles.length) {
      _count = widget.services.store.articles.length;
      _search();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 15),
        child: TextField(
          controller: _query,
          decoration: InputDecoration(
            hintText: 'Пошук у твоїх матеріалах',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Знайти',
              onPressed: () {
                setState(() {
                  _term = _query.text;
                  _search();
                });
              },
              icon: const Icon(Icons.search_rounded),
            ),
          ),
          onSubmitted: (v) => setState(() {
            _term = v;
            _search();
          }),
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
              return const EmptyState(
                'Нічого не знайдено',
                'Спробуй інше слово або додай власні матеріали.',
                icon: Icons.search_off_rounded,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
              itemCount: articles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = articles[i];
                return Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    leading: Icon(
                      Icons.article_outlined,
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
                    trailing: const Icon(Icons.chevron_right_rounded),
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

void openArticle(
  BuildContext context,
  Article article,
  Services services,
  void Function(int) navigate,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Довідник')),
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
                final text =
                    '${article.title}\n\n${article.body}\n\n${article.license}';
                await services.store.setDraft(
                  text.substring(0, text.length.clamp(0, 4000)),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  navigate(4);
                }
              }),
            ),
          ],
        ),
      ),
    ),
  );
}

void unawaitedAsk(Services s, String question) {
  s.assistant.ask(question);
}
