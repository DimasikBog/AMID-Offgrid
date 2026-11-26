import 'package:flutter/material.dart';

import 'common.dart';
import '../models/appearance.dart';

ThemeData offgridTheme(Brightness brightness, {String style = 'forest'}) {
  final dark = brightness == Brightness.dark;
  final preset = appearancePresets.firstWhere(
    (p) => p.id == style,
    orElse: () => appearancePresets.first,
  );
  final radius = preset.radius;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff326550),
        brightness: brightness,
      ).copyWith(
        primary: dark ? mint : const Color(0xff265b45),
        onPrimary: dark ? ink : Colors.white,
        surface: dark ? const Color(0xff101b19) : const Color(0xfff7f8f4),
        surfaceContainerLow: dark ? const Color(0xff192622) : Colors.white,
        surfaceContainerHighest: dark
            ? const Color(0xff263b32)
            : const Color(0xffeaf0e9),
        outlineVariant: dark
            ? const Color(0xff34473e)
            : const Color(0xffdfe6dd),
        onSurface: dark ? const Color(0xffe2ece4) : ink,
        onSurfaceVariant: dark
            ? const Color(0xffafc0b5)
            : const Color(0xff596b60),
      );
  final scheme = style == 'forest'
      ? colors
      : ColorScheme.fromSeed(
          seedColor: Color(preset.seed),
          brightness: brightness,
        ).copyWith(
          primary: Color(dark ? preset.darkAccent : preset.lightAccent),
          onPrimary: dark ? const Color(0xff101018) : Colors.white,
          secondary: style == 'cyberpunk'
              ? (dark ? const Color(0xffff8fd6) : const Color(0xff9a286e))
              : null,
          surface: Color(dark ? preset.darkSurface : preset.lightSurface),
          surfaceContainerLow: Color.alphaBlend(
            Color(preset.seed).withValues(alpha: dark ? .12 : .025),
            Color(dark ? preset.darkSurface : 0xffffffff),
          ),
        );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      fontFamily: 'Roboto',
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 24,
      toolbarHeight: 72,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(style == 'forest' ? 16 : radius),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(17),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      height: 78,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: scheme.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style == 'forest' ? 12 : radius),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style == 'forest' ? 18 : radius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    ),
  );
}
