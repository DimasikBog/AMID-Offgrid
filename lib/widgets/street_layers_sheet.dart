import 'package:flutter/material.dart';

import '../models/street_map.dart';
import '../services/street_service.dart';
import 'common.dart';
import 'street_credits.dart';

class StreetLayersSheet extends StatelessWidget {
  const StreetLayersSheet({
    super.key,
    required this.streets,
    required this.select,
    required this.download,
    required this.catalog,
  });
  final StreetService streets;
  final Future<void> Function(String) select;
  final VoidCallback download, catalog;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListenableBuilder(
      listenable: Listenable.merge([streets, streets.store]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Твої карти',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Вулиці, будівлі та стежки'),
              subtitle: const Text('Онлайн · Protomaps / OpenStreetMap'),
              trailing: streets.mode == 'online'
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () => select('online'),
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Оглядова карта світу'),
              subtitle: const Text('Завжди офлайн · без вулиць'),
              trailing: streets.mode == 'overview'
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () => select('overview'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: streets.busy ? null : download,
              icon: const Icon(Icons.download_for_offline_outlined),
              label: const Text('Зберегти видиму область офлайн'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Наблизь потрібне місто або район перед завантаженням. Збережена область містить дороги й назви у вибраному масштабі; завантаження всього світу не потрібне.',
            ),
            const Section('Збережені області'),
            if (streets.store.streetRegions.isEmpty)
              const Text(
                'Областей ще немає. Збережи першу — вона працюватиме без інтернету.',
              ),
            for (final region in streets.store.streetRegions)
              ListTile(
                leading: Icon(
                  streets.mode == region.id
                      ? Icons.offline_pin
                      : Icons.map_outlined,
                ),
                title: Text(region.title),
                subtitle: Text(
                  '${(region.bytes / 1048576).toStringAsFixed(1)} MiB · деталізація ${region.maxZoom}',
                ),
                onTap: () => select(region.id),
                trailing: IconButton(
                  tooltip: 'Видалити ${region.title}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: streets.busy
                      ? null
                      : () => guarded(context, () async {
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Видалити «${region.title}»?'),
                              content: const Text(
                                'Завантажені вулиці цієї області буде прибрано. Твої точки й інші карти залишаться.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Назад'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Видалити'),
                                ),
                              ],
                            ),
                          );
                          if (yes == true) await streets.delete(region);
                        }),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              '${(streets.store.streetRegions.fold<int>(0, (n, r) => n + r.bytes) / 1048576).toStringAsFixed(1)} / ${maxStreetStorageBytes ~/ 1048576} MiB на пристрої',
            ),
            TextButton.icon(
              onPressed: catalog,
              icon: const Icon(Icons.layers_outlined),
              label: const Text('Інші карти та імпорт MBTiles'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Вулиці — знімок відкритих даних OSM, а не інформація про перекриття в реальному часі. Видимі онлайн-ділянки запитуються у джерела; збережені області читаються з пристрою.',
            ),
            if (streets.dataDate.isNotEmpty)
              Text('Дата файлу джерела: ${streets.dataDate}'),
            const StreetCredits(),
          ],
        ),
      ),
    ),
  );
}
