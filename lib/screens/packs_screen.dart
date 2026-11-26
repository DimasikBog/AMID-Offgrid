import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/services.dart';
import '../widgets/common.dart';
import '../widgets/password_dialog.dart';
import '../version.dart';
import '../widgets/starter_setup_panel.dart';
import 'privacy_screen.dart';
import 'catalog_screen.dart';
import 'account_screen.dart';
import 'appearance_screen.dart';

class PacksScreen extends StatelessWidget {
  const PacksScreen({super.key, required this.services, this.openMap});
  final Services services;
  final VoidCallback? openMap;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.store,
      services.files,
      services.assistant,
      services.setup,
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
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CatalogScreen(services: services, openMap: openMap),
                    ),
                  ),
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('Каталог карт і ШІ'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AccountScreen(account: services.account),
                    ),
                  ),
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Мій акаунт'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            StarterSetupPanel(setup: services.setup),
            const SizedBox(height: 20),
            const Section('Додаткові файли й власні карти'),
            FilledButton.icon(
              onPressed: files.busy
                  ? null
                  : () => guarded(
                      context,
                      () => files.pick(
                        requestPassword: () => requestBackupPassword(context),
                      ),
                    ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Імпортувати файл'),
            ),
            const SizedBox(height: 8),
            const Text(
              'TXT · MD · AMID JSON · GeoJSON · MBTiles · GGUF · захищена копія',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
            if (files.busy) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: files.progress == 0 ? null : files.progress,
              ),
              const SizedBox(height: 10),
              Text(files.label),
              TextButton(
                onPressed: files.cancel,
                child: const Text('Скасувати дію'),
              ),
            ],
            const Section('На цьому пристрої'),
            for (final p in store.packs)
              if (p['kind'] != 'atlas')
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
                          p['routing'] is Map
                              ? '${((p['routing'] as Map)['nodes'] as List).length} вузлів · ${((p['routing'] as Map)['edges'] as List).length} ділянок маршрутизації'
                              : p['kind'] == 'knowledge'
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
                    'Статті, нотатки, обране, чернетка й точки — однією копією. Моделі та MBTiles зберігай окремо. Звичайний JSON містить відкритий текст; захищена копія потребує пароля.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: files.busy || ai.loading || ai.generating
                        ? null
                        : () => guarded(context, files.exportBackup),
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Зберегти JSON без пароля'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: files.busy || ai.loading || ai.generating
                        ? null
                        : () => guarded(context, () async {
                            final password = await requestBackupPassword(
                              context,
                              creating: true,
                            );
                            if (password == null) return null;
                            await files.exportBackup(password: password);
                            return 'Захищену копію збережено.';
                          }),
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: const Text('Зберегти копію з паролем'),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Щоб відновити копію, імпортуй її як звичайний файл.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const Section('Точки та вільне місце'),
            OutlinedButton.icon(
              onPressed: files.busy || store.pins.isEmpty
                  ? null
                  : () => guarded(context, files.exportPins),
              icon: const Icon(Icons.place_outlined),
              label: const Text('Експортувати точки GeoJSON'),
            ),
            if (!kIsWeb)
              TextButton.icon(
                onPressed: files.busy
                    ? null
                    : () => guarded(context, files.clearTemporaryFiles),
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Очистити незавершені завантаження'),
              ),
            const Section('Вигляд'),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => AppearanceScreen(store: store),
                ),
              ),
              icon: const Icon(Icons.palette_outlined),
              label: const Text('Стилі оформлення · 10 варіантів'),
            ),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: store.themePreference,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: 'system',
                  child: Text('Як на пристрої'),
                ),
                DropdownMenuItem(value: 'light', child: Text('Світла тема')),
                DropdownMenuItem(value: 'dark', child: Text('Темна тема')),
              ],
              onChanged: (value) {
                if (value != null) {
                  guarded(context, () => store.setThemePreference(value));
                }
              },
            ),
            const Section('Про застосунок'),
            Text(
              'AMID Offgrid · $appVersion\\nFlutter для телефонів, комп’ютерів і web; окремі мініклієнти годинників\\nКарти світу: Natural Earth, public domain.\\nДетальні вулиці: Protomaps / OpenStreetMap (ODbL), збереження областей офлайн. Пошук адрес і розрахунок маршрутів по дорогах — онлайн; збережені маршрути доступні офлайн без перерахунку. Офлайн-розрахунок — через імпортовану мережу AMID. ZIM-Вікіпедія ще не додана.\\nBluetooth: прямий сеанс між двома AMID; сумісність із Briar/BitChat не заявляється.'
                  .replaceAll(r'\n', '\n'),
              style: TextStyle(height: 1.7),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const PrivacyScreen()),
              ),
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Дані та приватність'),
            ),
            TextButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'AMID Offgrid',
                applicationVersion: appVersion,
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
