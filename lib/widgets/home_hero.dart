import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/store.dart';
import '../models/appearance.dart';
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
      final preset = appearancePresets.firstWhere(
        (p) => p.id == store.themeStyle,
      );
      final custom = preset.id != 'forest';
      final accent = custom ? Color(preset.darkAccent) : mint;
      final backdrop = Color(preset.darkSurface);

      final wide =
          size.maxWidth >= 720 &&
          MediaQuery.textScalerOf(context).scale(14) < 22;
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: accent.withValues(alpha: .18)),
            ),
            child: Text(
              'СВОБОДА БУТИ ОФЛАЙН',
              style: TextStyle(
                color: accent,
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Твій світ.\nБез мережі.',
            style: TextStyle(
              color: Colors.white,
              fontSize: wide ? 48 : 36,
              height: 1.08,
              letterSpacing: -1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Знання, карти та власні матеріали.\nПоруч, куди б ти не вирушив.',
            style: TextStyle(
              color: Color(0xffd0e0d4),
              height: 1.6,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: openPacks,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: ink,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
            ),
            icon: const Icon(Icons.offline_pin_outlined, size: 20),
            label: Text(
              preparing
                  ? 'Готую офлайн-набір…'
                  : needsSetup
                  ? 'Встановити все'
                  : 'Мій офлайн-набір',
            ),
          ),
          if (preparing) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              color: accent,
              backgroundColor: Colors.white.withValues(alpha: .15),
            ),
            const SizedBox(height: 8),
            Text(
              'Підготовка на пристрої. Відкрий набір, щоб переглянути стан.',
              style: TextStyle(color: accent, fontSize: 12),
            ),
          ],
        ],
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(custom ? preset.radius : 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: custom
                  ? [
                      backdrop,
                      Color.alphaBlend(
                        Color(preset.seed).withValues(alpha: .2),
                        backdrop,
                      ),
                    ]
                  : const [Color(0xff153d31), Color(0xff284e3f)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _Contours(color: accent)),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(wide ? 36 : 26),
                child: wide
                    ? Row(
                        children: [
                          Expanded(child: content),
                          const SizedBox(width: 32),
                          SizedBox(width: 214, child: _FieldCard(store: store)),
                        ],
                      )
                    : content,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final preset = appearancePresets.firstWhere(
      (p) => p.id == store.themeStyle,
    );
    final accent = preset.id == 'forest' ? mint : Color(preset.darkAccent);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color:
            (preset.id == 'forest'
                    ? const Color(0xff173e32)
                    : Color(preset.darkSurface))
                .withValues(alpha: .8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.explore_outlined, color: accent, size: 36),
          const SizedBox(height: 28),
          Text(
            'ТВІЙ БАГАЖ ЗНАНЬ',
            style: TextStyle(
              color: accent,
              fontSize: 10,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${store.articles.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              height: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'матеріалів на пристрої',
            style: TextStyle(color: Color(0xffd0e0d4), fontSize: 12),
          ),
          const SizedBox(height: 20),
          Divider(color: accent.withValues(alpha: .2)),
          const SizedBox(height: 8),
          Text(
            '${store.favoriteKeys.length} в обраному · ${store.pins.length} точок',
            style: TextStyle(color: accent, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Static decoration: no location access, network tiles or animation.
class _Contours extends CustomPainter {
  const _Contours({this.color = mint});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .93, size.height * .72);
    final paint = Paint()
      ..color = color.withValues(alpha: .1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var ring = 1; ring <= 16; ring++) {
      final path = Path();
      for (var step = 0; step <= 100; step++) {
        final a = step * math.pi * 2 / 100;
        final radius = ring * 21.0 + math.sin(a * 3 + ring * .25) * 13;
        final point =
            center +
            Offset(math.cos(a) * radius * 1.3, math.sin(a) * radius * .9);
        if (step == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path..close(), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Contours oldDelegate) => false;
}
