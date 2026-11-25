import 'package:flutter/material.dart';

import 'common.dart';

ThemeData offgridTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
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
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      fontFamily: 'Roboto',
      bodyColor: colors.onSurface,
      displayColor: colors.onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 24,
      toolbarHeight: 72,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(17),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainerLow,
      indicatorColor: colors.primaryContainer,
      height: 78,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
      selectedIconTheme: IconThemeData(color: colors.primary),
      unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: colors.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: colors.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(color: colors.outlineVariant, thickness: 1),
    chipTheme: ChipThemeData(
      side: BorderSide(color: colors.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
