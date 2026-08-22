import 'package:flutter/material.dart';

abstract class CineoColors {
  static const background = Color(0xFF090A0C);
  static const surface = Color(0xFF16181D);
  static const surfaceElevated = Color(0xFF20232A);
  static const primary = Color(0xFFE34C51);
  static const textPrimary = Color(0xFFF4F4F5);
  static const textSecondary = Color(0xFFAAADB5);
  static const divider = Color(0xFF2A2D33);
}

ThemeData buildCineoTheme() {
  const scheme = ColorScheme.dark(
    primary: CineoColors.primary,
    secondary: CineoColors.primary,
    surface: CineoColors.surface,
    background: CineoColors.background,
    onPrimary: Colors.white,
    onSurface: CineoColors.textPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: CineoColors.background,
    dividerColor: CineoColors.divider,
    appBarTheme: const AppBarTheme(
      backgroundColor: CineoColors.background,
      foregroundColor: CineoColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardTheme(
      color: CineoColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: CineoColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: CineoColors.primary),
      ),
    ),
  );
}
