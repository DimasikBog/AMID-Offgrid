import 'package:flutter/material.dart';

import 'common.dart';

/// A content-driven grid keeps cards usable with large accessibility text.
class DashboardGrid extends StatelessWidget {
  const DashboardGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) >= 22;
      final columns = largeText && size.maxWidth < 600
          ? 1
          : size.maxWidth >= 900
          ? 4
          : 2;
      final width = (size.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.index,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = switch (index) {
      1 => dark ? const Color(0xffb9c7ef) : const Color(0xff596c9e),
      2 => dark ? const Color(0xffecd2a1) : const Color(0xff88652c),
      3 => dark ? const Color(0xffa5d4da) : const Color(0xff366f79),
      _ => colors.primary,
    };
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .75)),
        borderRadius: BorderRadius.circular(22),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 24, color: accent),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.north_east_rounded,
                    size: 17,
                    color: colors.outline,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardSearch extends StatelessWidget {
  const DashboardSearch({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Що хочеш знайти?',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: colors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CollectionSummary extends StatelessWidget {
  const CollectionSummary({
    super.key,
    required this.articles,
    required this.favorites,
    required this.pins,
    required this.navigate,
    required this.openFavorites,
  });
  final int articles, favorites, pins;
  final void Function(int) navigate;
  final VoidCallback openFavorites;

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(6),
    child: LayoutBuilder(
      builder: (context, size) {
        final stacked = MediaQuery.textScalerOf(context).scale(14) > 22;
        final entries = [
          _Counter(
            '$articles',
            'матеріалів',
            Icons.menu_book_outlined,
            () => navigate(1),
          ),
          _Counter(
            '$favorites',
            'в обраному',
            Icons.star_outline_rounded,
            openFavorites,
          ),
          _Counter(
            '$pins',
            'точок на карті',
            Icons.place_outlined,
            () => navigate(3),
          ),
        ];
        return stacked
            ? Column(children: entries)
            : Row(
                children: [for (final entry in entries) Expanded(child: entry)],
              );
      },
    ),
  );
}

class _Counter extends StatelessWidget {
  const _Counter(this.count, this.label, this.icon, this.onTap);
  final String count, label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(height: 8),
              Text(
                count,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
