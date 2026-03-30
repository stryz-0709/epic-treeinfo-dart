import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color palette with green accents – mirrors the ThingsBoardApp reference.
class AppColors {
  // Core
  static const background = Color(0xFFF4FAF5);
  static const surface = Color(0xFFEAF5EC);

  // Accent
  static const accentGreen = Color(0xFF4CAF50);
  static const accentGreenDark = Color(0xFF2E7D32);
  static const accent = Color(0xFF66BB6A);

  // Status
  static const success = Color(0xFF43A047);
  static const warning = Color(0xFF66BB6A);
  static const error = Color(0xFF2E7D32);

  // Incident UI
  static const incidentSeverityHigh = Color(0xFFB42318);
  static const incidentSeverityMedium = Color(0xFFB54708);
  static const incidentSeverityLow = Color(0xFF2E7D32);
  static const incidentSeverityDefault = Color(0xFF475467);
  static const incidentStatusOpen = Color(0xFF1565C0);
  static const incidentStatusInProgress = Color(0xFFF57C00);
  static const incidentStatusResolved = Color(0xFF2E7D32);
  static const incidentStatusDefault = Color(0xFF475467);

  // Text
  static const textPrimary = Color(0xFF183222);
  static const textSecondary = Color(0xFF4E6A59);
  static const textHint = Color(0xFF8AA393);
  static const versionLabel = Color(0xFF86A593);

  // Card
  static const cardBg = Color(0xEAF9FCFA);
  static const cardBorder = Color(0x1A3D8C56);

  // Dark mode
  static const darkBackground = Color(0xFF0F1B14);
  static const darkSurface = Color(0xFF15261D);
  static const darkCardBg = Color(0xFF1C3327);
  static const darkCardBorder = Color(0x337DB898);
  static const darkTextPrimary = Color(0xFFE2F2E8);
  static const darkTextSecondary = Color(0xFFA2C1AF);
}

class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadii {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

class AppShadows {
  static final surface = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  static final accent = [
    BoxShadow(
      color: AppColors.accentGreen.withValues(alpha: 0.25),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  static final danger = [
    BoxShadow(
      color: const Color(0xFFB42318).withValues(alpha: 0.25),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];
}

class AppTypography {
  static const title = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    height: 1.08,
  );

  static const subtitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static const sectionLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.1,
  );

  static const bodyStrong = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
}

ThemeData buildLightTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accentGreen,
      brightness: Brightness.light,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: AppColors.background.withValues(alpha: 0.96),
      indicatorColor: AppColors.accentGreen.withValues(alpha: 0.2),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.accentGreen);
        }
        return const IconThemeData(color: AppColors.textSecondary);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: AppColors.accentGreen,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }
        return const TextStyle(color: AppColors.textSecondary, fontSize: 12);
      }),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    ),
    dividerColor: AppColors.accentGreen.withValues(alpha: 0.14),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accentGreen,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentGreenDark,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentGreenDark,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accentGreenDark,
        side: BorderSide(
          color: AppColors.accentGreen.withValues(alpha: 0.5),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.92),
      hintStyle: const TextStyle(color: AppColors.textHint),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: AppColors.accentGreen.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.accentGreenDark),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.accentGreenDark,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
  );
}

ThemeData buildDarkTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accentGreen,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
    ),
    scaffoldBackgroundColor: AppColors.darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBackground,
      foregroundColor: AppColors.darkTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.darkCardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        side: const BorderSide(color: AppColors.darkCardBorder),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: AppColors.darkSurface,
      indicatorColor: AppColors.accentGreen.withValues(alpha: 0.24),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.accentGreen);
        }
        return const IconThemeData(color: AppColors.darkTextSecondary);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: AppColors.accentGreen,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }
        return const TextStyle(color: AppColors.darkTextSecondary, fontSize: 12);
      }),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.darkCardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    ),
    dividerColor: AppColors.accentGreen.withValues(alpha: 0.2),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accentGreen,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentGreen,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentGreen,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accentGreen,
        side: BorderSide(
          color: AppColors.accentGreen.withValues(alpha: 0.6),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface.withValues(alpha: 0.92),
      hintStyle: const TextStyle(color: AppColors.darkTextSecondary),
      labelStyle: const TextStyle(color: AppColors.darkTextSecondary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: AppColors.accentGreen.withValues(alpha: 0.25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.accentGreen),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.accentGreen,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
  );
}
