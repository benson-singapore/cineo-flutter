import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract class CineoColors {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceElevated = Color(0xFF27272A);
  static const surfaceOverlay = Color(0xFF323236);
  static const primary = Color(0xFFFFA13A);
  static const primaryLight = Color(0xFFFFC467);
  static const primaryContainer = Color(0xFF4B2E13);
  static const textPrimary = Color(0xFFF8F7F4);
  static const textSecondary = Color(0xFFACA9A4);
  static const divider = Color(0xFF38383A);
  static const glass = Color(0xD91C1C1E);
}

ThemeData buildCineoTheme() {
  const scheme = ColorScheme.dark(
    primary: CineoColors.primary,
    onPrimary: Color(0xFF251300),
    primaryContainer: CineoColors.primaryContainer,
    onPrimaryContainer: CineoColors.primaryLight,
    secondary: CineoColors.primaryLight,
    surface: CineoColors.surface,
    background: CineoColors.background,
    onSurface: CineoColors.textPrimary,
    surfaceVariant: CineoColors.surfaceElevated,
    outline: CineoColors.divider,
    outlineVariant: CineoColors.divider,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: CineoColors.background,
    dividerColor: CineoColors.divider,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    cupertinoOverrideTheme: const CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: CineoColors.primary,
      scaffoldBackgroundColor: CineoColors.background,
      barBackgroundColor: CineoColors.glass,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(color: CineoColors.textPrimary),
        navTitleTextStyle: TextStyle(
          color: CineoColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        navLargeTitleTextStyle: TextStyle(
          color: CineoColors.textPrimary,
          fontSize: 34,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: CineoColors.background,
      foregroundColor: CineoColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: CineoColors.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: const CardTheme(
      color: CineoColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: CineoColors.surfaceElevated,
      hintStyle: TextStyle(color: CineoColors.textSecondary),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: CineoColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: CineoColors.primary, width: 1.5),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 76,
      backgroundColor: CineoColors.glass,
      surfaceTintColor: Colors.transparent,
      indicatorColor: CineoColors.primaryContainer,
      labelTextStyle: MaterialStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
      iconTheme: MaterialStatePropertyAll(
        IconThemeData(size: 24),
      ),
    ),
    tabBarTheme: const TabBarTheme(
      indicatorColor: CineoColors.primary,
      labelColor: CineoColors.primaryLight,
      unselectedLabelColor: CineoColors.textSecondary,
      labelStyle: TextStyle(fontWeight: FontWeight.w700),
      dividerColor: CineoColors.divider,
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: CineoColors.surfaceElevated,
      selectedColor: CineoColors.primaryContainer,
      secondarySelectedColor: CineoColors.primaryContainer,
      labelStyle: TextStyle(color: CineoColors.textPrimary),
      secondaryLabelStyle: TextStyle(
        color: CineoColors.primaryLight,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(color: CineoColors.divider),
      shape: StadiumBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CineoColors.primary,
        foregroundColor: const Color(0xFF251300),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CineoColors.textPrimary,
        side: const BorderSide(color: CineoColors.divider),
        shape: const StadiumBorder(),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: CineoColors.primary,
      foregroundColor: Color(0xFF251300),
      shape: StadiumBorder(),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CineoColors.primary,
      linearTrackColor: CineoColors.surfaceOverlay,
    ),
  );
}
