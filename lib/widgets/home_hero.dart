import 'package:flutter/material.dart';

import '../services/store.dart';
import 'common.dart';

class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.store,
    required this.openPacks,
    this.needsSetup = false,
    this.preparing = false,
    this.progress,
  });
  final bool needsSetup;
  final bool preparing;
  final double? progress;
  final AppStore store;
  final VoidCallback openPacks;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final wide = size.maxWidth >= 700;
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ТВІЙ ПРОСТІР AMID',
            style: TextStyle(color: mint, fontSize: 12, letterSpacing: 2),
          ),
          const SizedBox(height: 20),
          Text(
            'Твій світ.\nБез мережі.',
            style: TextStyle(
              color: Colors.white,
              fontSize: wide ? 46 : 36,
              height: 1.08,
              letterSpacing: -1.2,
              fontWeight: FontWeight.w600,
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
            style: FilledButton.styleFrom(
              backgroundColor: mint,
              foregroundColor: ink,
            ),
            icon: const Icon(Icons.download_rounded),
            label: Text(
              preparing
                  ? 'Готую офлайн-набір…'
                  : needsSetup
                  ? 'Встановити все'
                  : 'Мій офлайн-набір',
            ),
          ),
          if (preparing) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            const Text(
              'Підготовка на пристрої. Відкрий набір, щоб переглянути стан.',
              style: TextStyle(color: mint, fontSize: 12),
            ),
          ],
        ],
      );
      return Panel(
        padding: const EdgeInsets.all(25),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff16382e), Color(0xff355b42)],
        ),
        child: wide
            ? Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 24),
                  Container(
                    width: 230,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.offline_pin_outlined,
                          color: mint,
                          size: 38,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '${store.articles.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          'матеріалів на пристрої',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${store.favoriteKeys.length} в обраному · ${store.pins.length} точок',
                          style: const TextStyle(color: mint, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : content,
      );
    },
  );
}
