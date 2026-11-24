import 'package:flutter/material.dart';

import 'common.dart';

ThemeData offgridTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff456f52),
        brightness: brightness,
      ).copyWith(
        primary: dark ? mint : const Color(0xff315e40),
        onPrimary: dark ? ink : Colors.white,
        surface: dark ? const Color(0xff101b19) : const Color(0xfff7f8f2),
        surfaceContainerLow: dark
            ? const Color(0xff192622)
            : const Color(0xffeef1e8),
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
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
      height: 76,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
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
