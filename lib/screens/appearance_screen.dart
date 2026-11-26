import 'package:flutter/material.dart';

import '../models/appearance.dart';
import '../services/store.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Твій стиль')),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'AMID під тебе',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Обирай настрій інтерфейсу. Світлий або темний режим налаштовується окремо. Вибір зберігається без мережі та в активному офлайн-профілі.',
              ),
              const Section('Світло'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    'system': 'Як на пристрої',
                    'light': 'Світлий',
                    'dark': 'Темний',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: store.themePreference == entry.key,
                      onSelected: (_) => guarded(
                        context,
                        () => store.setThemePreference(entry.key),
                      ),
                    ),
                ],
              ),
              const Section('Колекція стилів'),
              LayoutBuilder(
                builder: (context, box) {
                  final largeText =
                      MediaQuery.textScalerOf(context).scale(16) > 24;
                  final columns = box.maxWidth >= 740
                      ? 3
                      : box.maxWidth >= 500 && !largeText
                      ? 2
                      : 1;
                  final width = (box.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final preset in appearancePresets)
                        SizedBox(
                          width: width,
                          child: _StyleCard(
                            preset: preset,
                            selected: store.themeStyle == preset.id,
                            onTap: () => guarded(
                              context,
                              () => store.setThemeStyle(preset.id),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Стилі не змінюють твої карти, моделі, файли чи дозволи. Розмір тексту читача можна налаштувати окремо у матеріалах.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });
  final AppearancePreset preset;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final preview = offgridTheme(Brightness.dark, style: preset.id).colorScheme;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: preset.name,
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(preset.radius),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('appearance-${preset.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 66,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: preview.surface,
                    borderRadius: BorderRadius.circular(preset.radius),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        preset.id == 'cyberpunk'
                            ? Icons.bolt
                            : Icons.explore_outlined,
                        color: preview.primary,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 95,
                              height: 6,
                              color: preview.primary,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 62,
                              height: 5,
                              color: preview.secondary,
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_circle, color: preview.primary),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  preset.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  preset.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
