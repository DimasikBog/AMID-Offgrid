import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/services.dart';
import '../services/importer.dart';
import '../widgets/common.dart';

class PacksScreen extends StatelessWidget {
  const PacksScreen({super.key, required this.services});
  final Services services;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.store,
      services.files,
      services.assistant,
    ]),
    builder: (context, _) {
      final files = services.files,
          ai = services.assistant,
          store = services.store;
      return Scaffold(
        appBar: AppBar(title: const Text('Мій офлайн-набір')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 35),
          children: [
            Text(
              'Збережи зараз.\\nВідкривай будь-коли.'.replaceAll(r'\n', '\n'),
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 15),
            const Text(
              'Матеріали, карти й модель зберігаються окремими пакетами. Великі файли додавай заздалегідь.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: files.busy ? null : () => guarded(context, files.pick),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Імпортувати файл'),
            ),
            const SizedBox(height: 8),
            const Text(
              'TXT · AMID JSON · GeoJSON · растрові MBTiles · GGUF',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
            if (files.busy) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(value: files.progress),
              const SizedBox(height: 10),
              Text(files.label),
              TextButton(
                onPressed: files.cancel,
                child: const Text('Зупинити завантаження'),
              ),
            ],
            const Section('Локальний ШІ'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Qwen3 · 0.6B · Q8',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${prettyBytes(ImportService.modelBytes)} · завантаження через інтернет один раз. Далі запити обчислюються на телефоні.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Потрібна також вільна оперативна пам’ять. Швидкість залежить від телефону. Можна імпортувати іншу сумісну GGUF-модель.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 15),
                  OutlinedButton.icon(
                    onPressed:
                        kIsWeb ||
                            files.busy ||
                            store.packs.any((p) => p['id'] == 'qwen3-06b-q8')
                        ? null
                        : () => guarded(context, files.downloadStarter),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      store.packs.any((p) => p['id'] == 'qwen3-06b-q8')
                          ? 'Модель уже збережена'
                          : 'Завантажити · 639 MB',
                    ),
                  ),
                  if (kIsWeb)
                    const Text(
                      'Завантаження моделі доступне у встановленому застосунку.',
                      style: TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
            const Section('На цьому пристрої'),
            for (final p in store.packs)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(switch (p['kind']) {
                            'model' => Icons.memory_rounded,
                            'map' => Icons.map_outlined,
                            _ => Icons.menu_book_rounded,
                          }, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p['title'] as String,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (p['id'] != 'amid-mobile-starter')
                            IconButton(
                              tooltip: 'Видалити пакет',
                              onPressed:
                                  files.busy || ai.loading || ai.generating
                                  ? null
                                  : () => _remove(context, p),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p['kind'] == 'knowledge'
                            ? '${p['count']} статей'
                            : '${prettyBytes(p['bytes'] as int? ?? 0)} · ${p['kind'] == 'model' ? 'Модель GGUF' : 'Карта MBTiles'}',
                      ),
                      if (p['license'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Text(
                            p['license'] as String,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (p['sha256'] != null)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text(
                            'Контрольна сума',
                            style: TextStyle(fontSize: 12),
                          ),
                          children: [
                            SelectableText(
                              p['sha256'] as String,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      if (p['kind'] == 'model')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: FilledButton.tonalIcon(
                            onPressed: ai.loading || ai.generating
                                ? null
                                : () => guarded(context, () async {
                                    if (ai.loadedId == p['id']) {
                                      await ai.unload();
                                      return 'Модель вивантажена з пам’яті.';
                                    }
                                    await ai.load(p);
                                    return 'Модель готова до запитів.';
                                  }),
                            icon: Icon(
                              ai.loadedId == p['id']
                                  ? Icons.stop_circle_outlined
                                  : Icons.play_circle_outline_rounded,
                            ),
                            label: Text(
                              ai.loading
                                  ? 'Завантажую в пам’ять…'
                                  : ai.loadedId == p['id']
                                  ? 'Вивантажити з пам’яті'
                                  : 'Запустити на телефоні',
                            ),
                          ),
                        ),
                      if (p['kind'] == 'map')
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: OutlinedButton(
                            onPressed: () => guarded(
                              context,
                              () => store.selectMap(p['id'] as String),
                            ),
                            child: Text(
                              store.selectedMap == p['id']
                                  ? 'Активна карта'
                                  : 'Відкрити цю карту',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const Section('Резервна копія'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Статті, точки й повідомлення — одним JSON-файлом. Моделі та MBTiles зберігай окремо. Експорт містить відкритий текст.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: files.busy || ai.loading || ai.generating
                        ? null
                        : () => guarded(context, files.exportBackup),
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Зберегти копію'),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Щоб відновити копію, імпортуй її як звичайний файл.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const Section('Про застосунок'),
            Text(
              'AMID Offgrid · 0.2.0\\nFlutter для Android та iPhone\\nКарти світу: Natural Earth, public domain.\\nОглядова карта не містить вулиць. Навігація маршрутами та ZIM-Вікіпедія ще не додані.\\nBluetooth: прямий сеанс між двома AMID; сумісність із Briar/BitChat не заявляється.'
                  .replaceAll(r'\n', '\n'),
              style: TextStyle(height: 1.7),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'AMID Offgrid',
                applicationVersion: '0.2.0',
                applicationLegalese: 'AMID · Open-source dependency notices',
              ),
              icon: const Icon(Icons.info_outline_rounded),
              label: const Text('Ліцензії компонентів'),
            ),
          ],
        ),
      );
    },
  );
  Future<void> _remove(BuildContext context, Json pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Видалити пакет?'),
        content: Text(
          '${pack['title']}\nЙого можна буде імпортувати повторно.',
        ),
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
    if (confirmed != true || !context.mounted) return;
    await guarded(context, () async {
      if (services.assistant.loadedId == pack['id']) {
        await services.assistant.unload();
      }
      await services.store.removePack(pack['id'] as String);
      await services.files.deleteAsset(pack);
      return 'Пакет видалено.';
    });
  }
}
