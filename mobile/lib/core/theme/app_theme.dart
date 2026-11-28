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

abstract final class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
}

abstract final class AppSpace {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
}

const tabularFigures = [FontFeature.tabularFigures()];

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
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'PlusJakartaSans',
  );
  final textTheme = base.textTheme
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: -0.2,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: AppColors.textMuted,
        ),
      )
      .apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      centerTitle: false,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontWeight: FontWeight.w700,
        fontSize: 22,
        color: AppColors.textPrimary,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.textMuted),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: const TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: const TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: AppColors.primaryContainer,
      checkmarkColor: AppColors.primary,
      side: WidgetStateBorderSide.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const BorderSide(color: AppColors.primary, width: 1.5)
            : const BorderSide(color: AppColors.outline),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      extendedTextStyle: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.primaryContainer,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: RoundedRectangleBorder(),
      collapsedShape: RoundedRectangleBorder(),
    ),
  );
}
