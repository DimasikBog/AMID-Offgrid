import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/catalog.dart';
import '../models/data.dart';
import '../services/services.dart';
import '../widgets/common.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.services, this.openMap});
  final Services services;
  final VoidCallback? openMap;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  int _category = 0;
  String _query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Карти та локальний ШІ')),
    body: ListenableBuilder(
      listenable: Listenable.merge([
        widget.services.store,
        widget.services.catalog,
        widget.services.files,
        widget.services.assistant,
      ]),
      builder: (context, _) => FutureBuilder<List<CatalogEntry>>(
        future: widget.services.catalog.entries,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyState(
              'Каталог недоступний',
              'Не вдалося прочитати список перевірених пакетів.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!
              .where(
                (e) =>
                    (_category == 1
                        ? e.model
                        : _category == 2
                        ? e.kind == 'source'
                        : !e.model && e.kind != 'source') &&
                    '${e.title} ${e.description}'.toLowerCase().contains(
                      _query,
                    ),
              )
              .toList();
          final catalog = widget.services.catalog,
              files = widget.services.files,
              ai = widget.services.assistant;
          final busy = catalog.busy || files.busy;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Text(
                    'Твоя бібліотека можливостей',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Обирай матеріал, переглянь ліцензію та розмір і встановлюй на цей пристрій. Карти й моделі залишаються локальними.',
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < 3; i++)
                        ChoiceChip(
                          label: Text(
                            const ['Карти', 'Локальний ШІ', 'Джерела'][i],
                          ),
                          selected: _category == i,
                          onSelected: (_) => setState(() => _category = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Знайти карту, рік або модель',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (text) =>
                        setState(() => _query = text.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 14),
                  if (_category == 0)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text(
                        'Оглядова карта країн світу вже входить у додаток. Історичні скани відкриваються як атлас; GPS до них не прив’язаний. Шари Natural Earth не містять детальних вулиць.',
                      ),
                    ),
                  if (_category == 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        kIsWeb
                            ? 'Локальні GGUF-моделі встановлюються й запускаються в нативному застосунку Android, iOS або комп’ютера. Вебверсія показує каталог.'
                            : 'Оцінка RAM приблизна: вона залежить від системи й контексту. Більша модель не гарантує правильності відповіді. Запити не надсилаються на сервер акаунтів.',
                      ),
                    ),
                  if (_category == 2)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text(
                        'Це зовнішні колекції, не готові пакети для встановлення. Наявність карти в інтернеті не означає право масово завантажувати її тайли. Підтримуються власні растрові MBTiles та GeoJSON.',
                      ),
                    ),
                  if (busy)
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: catalog.busy && !files.busy
                                ? (catalog.progress == 0
                                      ? null
                                      : catalog.progress)
                                : (files.progress == 0 ? null : files.progress),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            catalog.busy && !files.busy
                                ? catalog.label
                                : files.label,
                          ),
                          TextButton(
                            onPressed: catalog.cancel,
                            child: const Text(
                              'Скасувати · модель можна докачати',
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (entries.isEmpty)
                    const EmptyState(
                      'Нічого не знайдено',
                      'Спробуй інше слово або іншу категорію.',
                    ),
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  entry.model
                                      ? Icons.memory_outlined
                                      : entry.kind == 'source'
                                      ? Icons.travel_explore
                                      : entry.kind == 'image'
                                      ? Icons.history_edu_outlined
                                      : Icons.layers_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    entry.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(entry.description),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (entry.installable)
                                  Pill(prettyBytes(entry.bytes)),
                                if (entry.ramGiB > 0)
                                  Pill('RAM ≈ ${entry.ramGiB}+ GiB'),
                                if (catalog.installed(entry))
                                  const Pill('На пристрої'),
                                Pill(
                                  entry.kind == 'image'
                                      ? 'Атлас'
                                      : entry.kind == 'geojson'
                                      ? 'Шар GeoJSON'
                                      : entry.model
                                      ? 'GGUF'
                                      : 'Колекція',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              entry.license,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (entry.installable &&
                                    !catalog.installed(entry))
                                  FilledButton.icon(
                                    onPressed:
                                        busy ||
                                            ai.busy ||
                                            (entry.model && kIsWeb)
                                        ? null
                                        : () => guarded(
                                            context,
                                            () => _install(entry),
                                          ),
                                    icon: const Icon(Icons.download_outlined),
                                    label: const Text('Встановити'),
                                  ),
                                if (catalog.installed(entry))
                                  FilledButton.tonalIcon(
                                    onPressed: busy || ai.busy
                                        ? null
                                        : () => guarded(context, () async {
                                            if (entry.kind == 'image') {
                                              await _image(entry);
                                            } else if (entry.model) {
                                              await ai.unload();
                                              await widget.services.store
                                                  .selectModel(entry.id);
                                              return 'Модель обрана. Запуститься з наступним запитом.';
                                            } else {
                                              widget.openMap?.call();
                                              return widget.openMap == null
                                                  ? 'Шар доступний у вкладці «Карта».'
                                                  : null;
                                            }
                                            return null;
                                          }),
                                    icon: Icon(
                                      entry.model
                                          ? Icons.check_circle_outline
                                          : Icons.open_in_full,
                                    ),
                                    label: Text(
                                      entry.model
                                          ? (widget
                                                        .services
                                                        .store
                                                        .selectedModel ==
                                                    entry.id
                                                ? 'Обрано'
                                                : 'Вибрати')
                                          : 'Відкрити',
                                    ),
                                  ),
                                if (widget.services.store.packs.any(
                                  (p) => p['id'] == entry.id,
                                ))
                                  IconButton(
                                    tooltip: 'Видалити з пристрою',
                                    onPressed: busy || ai.busy
                                        ? null
                                        : () => guarded(
                                            context,
                                            () => _remove(entry),
                                          ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                TextButton.icon(
                                  onPressed: () => guarded(context, () async {
                                    if (!await launchUrl(
                                      Uri.parse(entry.source),
                                      mode: LaunchMode.externalApplication,
                                    )) {
                                      throw StateError(
                                        'Не вдалося відкрити джерело.',
                                      );
                                    }
                                  }),
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  label: const Text('Джерело'),
                                ),
                              ],
                            ),
                            if (entry.installable)
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text(
                                  'Цілісність файла',
                                  style: TextStyle(fontSize: 12),
                                ),
                                children: [
                                  SelectableText(
                                    'SHA-256: ${entry.sha256}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
  Future<String> _install(CatalogEntry entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Встановити ${entry.title}?'),
        content: Text(
          '${prettyBytes(entry.bytes)} буде завантажено з ${entry.url!.host}.\n\n${entry.license}${entry.model ? '\n\nПотрібна вільна оперативна пам’ять; оцінка каталогу не є гарантією сумісності.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Завантажити'),
          ),
        ],
      ),
    );
    if (yes != true) return '';
    await widget.services.catalog.install(entry);
    return 'Пакет збережено на пристрої.';
  }

  Future<void> _remove(CatalogEntry entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Видалити встановлений пакет?'),
        content: Text(entry.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Залишити'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    if (widget.services.assistant.loadedId == entry.id) {
      await widget.services.assistant.unload();
    }
    final pack = widget.services.store.packs
        .where((p) => p['id'] == entry.id)
        .firstOrNull;
    if (entry.model && pack != null) {
      await widget.services.files.deleteAsset(pack);
    }
    await widget.services.catalog.remove(entry);
  }

  Future<void> _image(CatalogEntry entry) async {
    final bytes = await widget.services.catalog.image(entry);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(entry.title)),
          body: Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 12,
                  child: Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('Не вдалося відкрити зображення.'),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${entry.license}\nАрхівне зображення · GPS не прив’язаний',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
