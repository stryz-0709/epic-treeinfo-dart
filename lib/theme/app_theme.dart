import 'package:flutter/material.dart';

/// Color palette with green accents – mirrors the ThingsBoardApp reference.
class AppColors {
  // Core
  static const background = Colors.white;
  static const surface = Color(0xFFF8F9FA);

  // Accent
  static const accentGreen = Color(0xFF4CAF50);
  static const accentGreenDark = Color(0xFF2E7D32);
  static const accent = Color(0xFF00ACC1);

  // Status
  static const success = Color(0xFF4CAF50);
  static const warning = Color(0xFFFFA726);
  static const error = Color(0xFFEF5350);

  // Text
  static const textPrimary = Color(0xFF1B2838);
  static const textSecondary = Color(0xFF777777);
  static const textHint = Color(0xFFAAAAAA);

  // Card
  static const cardBg = Color(0xDDFFFFFF);
  static const cardBorder = Color(0x14000000);

  // Dark mode
  static const darkBackground = Color(0xFF121212);
  static const darkSurface = Color(0xFF1E1E1E);
  static const darkCardBg = Color(0xFF2C2C2C);
  static const darkCardBorder = Color(0x33FFFFFF);
  static const darkTextPrimary = Color(0xFFE0E0E0);
  static const darkTextSecondary = Color(0xFF999999);
}

ThemeData buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accentGreen,
      brightness: Brightness.light,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      indicatorColor: AppColors.accentGreen.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.accentGreen);
        }
        return const IconThemeData(color: Color(0xFF999999));
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: AppColors.accentGreen,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }
        return const TextStyle(color: Color(0xFF999999), fontSize: 12);
      }),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerColor: Colors.black.withValues(alpha: 0.08),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accentGreen,
    ),
  );
}

ThemeData buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accentGreen,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
    ),
    scaffoldBackgroundColor: AppColors.darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: AppColors.darkTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.darkCardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.darkCardBorder),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: const Color(0xFF1E1E1E),
      indicatorColor: AppColors.accentGreen.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.accentGreen);
        }
        return const IconThemeData(color: Color(0xFF999999));
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: AppColors.accentGreen,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }
        return const TextStyle(color: Color(0xFF999999), fontSize: 12);
      }),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF2C2C2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerColor: Colors.white.withValues(alpha: 0.08),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accentGreen,
    ),
  );
}
