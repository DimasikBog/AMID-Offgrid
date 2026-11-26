import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/services.dart';
import '../widgets/common.dart';
import 'emergency_screen.dart';

/// A live inventory, not a network, file-integrity or emergency-service test.
class PreparationScreen extends StatefulWidget {
  const PreparationScreen({
    super.key,
    required this.services,
    required this.openPacks,
    this.openMap,
  });
  final Services services;
  final VoidCallback openPacks;
  final VoidCallback? openMap;

  @override
  State<PreparationScreen> createState() => _PreparationScreenState();
}

class _PreparationScreenState extends State<PreparationScreen> {
  Services get services => widget.services;
  VoidCallback get openPacks => widget.openPacks;
  VoidCallback? get openMap => widget.openMap;
  String? _openingRegionId;

  Future<void> _openRegion(BuildContext context, String id) async {
    if (_openingRegionId != null || openMap == null) return;
    setState(() => _openingRegionId = id);
    try {
      await guarded(context, () async {
        await services.store.selectMap('');
        if (!context.mounted) return;
        await services.streets.selectMode(id);
        if (!context.mounted ||
            services.streets.mode != id ||
            services.streets.loading) {
          return;
        }
        final error = services.streets.error;
        if (error != null) throw StateError(error);
        openMap?.call();
      });
    } finally {
      if (mounted) setState(() => _openingRegionId = null);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.store,
      services.assistant,
      services.streets,
    ]),
    builder: (context, _) {
      final store = services.store;
      final models = store.packs.where((p) => p['kind'] == 'model').length;
      final maps = store.packs.where((p) => p['kind'] == 'map').length;
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(title: const Text('Перед дорогою')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Panel(
                  color: colors.primaryContainer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.backpack_outlined,
                        color: colors.onPrimaryContainer,
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Твій набір для дороги',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: colors.onPrimaryContainer),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Відкрий потрібну область карти й постав запит ШІ в режимі польоту до поїздки. Цей огляд не перевіряє доступність зв’язку чи цілісність файлів.',
                        style: TextStyle(color: colors.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
                const Section('Карти та місця'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.streetRegions.isEmpty
                            ? 'Детальні вулиці ще не збережені'
                            : 'Областей з вулицями: ${store.streetRegions.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Огляд світу не містить усіх вулиць. Збережи потрібну область на екрані карти.',
                      ),
                      for (final region in store.streetRegions)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: TextButton.icon(
                            key: ValueKey('prepared-region-${region.id}'),
                            onPressed:
                                openMap == null ||
                                    _openingRegionId != null ||
                                    services.streets.loading
                                ? null
                                : () => _openRegion(context, region.id),
                            icon: _openingRegionId == region.id
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.offline_pin_outlined),
                            label: Text(
                              '${region.title} · масштаб до ${region.maxZoom} · ${prettyBytes(region.bytes)}',
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        'Власні карти MBTiles: $maps · збережені точки: ${store.pins.length}',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: openMap,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Відкрити карту'),
                      ),
                    ],
                  ),
                ),
                const Section('Матеріали та помічник'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Матеріалів у бібліотеці: ${store.articles.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        kIsWeb
                            ? 'У вебверсії працює пошук у матеріалах. GGUF потребує нативної програми.'
                            : 'Збережених GGUF-моделей: $models. ${services.assistant.ready ? 'Модель у пам’яті.' : 'Модель зараз не завантажена у пам’ять.'}',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Зовнішні посилання можуть потребувати інтернету. Збережені моделі й детальні карти не входять у резервну копію матеріалів.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: openPacks,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Офлайн-набір і резервна копія'),
                      ),
                    ],
                  ),
                ),
                const Section('Перевір SOS заздалегідь'),
                const Text(
                  'Дозволи GPS і мікрофона краще налаштувати до поїздки. Тренування не телефонує й не надсилає SMS. Реальному зверненню потрібен телефонний зв’язок; AMID не підтверджує отримання службою.',
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const EmergencyScreen(initialTraining: true),
                    ),
                  ),
                  icon: const Icon(Icons.school_outlined),
                  label: const Text('Відкрити тренування SOS'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
