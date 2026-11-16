import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF0F4C5C);
  static const primaryContainer = Color(0xFFD8EEF3);
  static const background = Color(0xFFF8FAFC);
  static const card = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFEFF3F7);
  static const outline = Color(0xFFCBD5E1);
  static const textPrimary = Color(0xFF0F172A);
  static const textMuted = Color(0xFF475569);
  static const error = Color(0xFFB3261E);
  static const warning = Color(0xFFB45309);
  static const success = Color(0xFF0F766E);
  static const information = Color(0xFF1D4ED8);
  static const simulation = Color(0xFF3730A3);
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.primary,
    surface: AppColors.card,
    surfaceContainerHighest: AppColors.surfaceVariant,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.outline,
    error: AppColors.error,
    onError: Colors.white,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.textMuted),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.all(16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.primaryContainer,
    ),
  );
}
