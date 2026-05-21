import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFFF7F7FB);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE6E6F0);

  // พีพี brand color — สีน้ำเงิน
  static const primary = Color(0xFF1E2B8C);
  static const primaryHover = Color(0xFF2A3FB8); // อ่อนกว่า primary เล็กน้อย

  static const accent = Color(0xFFFBBF24);
  static const accentHover = Color(0xFFF59E0B);

  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const danger = Color(0xFFEF4444);
}

class AppColorsDark {
  static const bg = Color(0xFF0F172A); // Slate 950
  static const surface = Color(0xFF1E293B); // Slate 800
  static const border = Color(0xFF334155); // Slate 700
  // Dark theme variant of พีพี brand blue — slightly brighter for contrast on dark bg
  static const primary = Color(0xFF4A5DD8); // brighter blue for dark mode
  static const primaryHover = Color(0xFF6577E2);
  static const accent = Color(0xFFFCD34D); // Amber 300
  static const text = Color(0xFFF1F5F9); // Slate 100
  static const muted = Color(0xFF94A3B8); // Slate 400
  static const danger = Color(0xFFF87171); // Red 400
}

/// Context extension — resolves to dark or light token based on current theme.
extension AppColorsExt on BuildContext {
  bool get _dark => Theme.of(this).brightness == Brightness.dark;
  Color get colorBg      => _dark ? AppColorsDark.bg      : AppColors.bg;
  Color get colorSurface => _dark ? AppColorsDark.surface : AppColors.surface;
  Color get colorBorder  => _dark ? AppColorsDark.border  : AppColors.border;
  Color get colorPrimary => _dark ? AppColorsDark.primary : AppColors.primary;
  Color get colorMuted   => _dark ? AppColorsDark.muted   : AppColors.muted;
  Color get colorText    => _dark ? AppColorsDark.text    : AppColors.text;
  Color get colorDanger  => _dark ? AppColorsDark.danger  : AppColors.danger;
  Color get colorAccent  => _dark ? AppColorsDark.accent  : AppColors.accent;
}

class AppSizes {
  static const radius = 16.0;
  static const gap = 12.0;
  static const borderWidth = 1.2;
}

class AppShadows {
  static const soft = [
    BoxShadow(
      color: Color(0x0F000000),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -8,
    ),
  ];
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: AppColors.text,
        onSurface: AppColors.text,
        onError: Colors.white,
        outlineVariant: AppColors.border,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.text,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          side: const BorderSide(color: AppColors.border),
        ),
        elevation: 0,
        margin: const EdgeInsets.all(AppSizes.gap),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        hintStyle: const TextStyle(color: AppColors.muted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          side: const BorderSide(color: AppColors.border),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.text,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColorsDark.bg,
      colorScheme: ColorScheme.dark(
        primary: AppColorsDark.primary,
        secondary: AppColorsDark.accent,
        surface: AppColorsDark.surface,
        error: AppColorsDark.danger,
        onPrimary: Colors.white,
        onSecondary: AppColorsDark.text,
        onSurface: AppColorsDark.text,
        onError: Colors.white,
        outlineVariant: AppColorsDark.border,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColorsDark.text,
        displayColor: AppColorsDark.text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColorsDark.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColorsDark.text,
      ),
      cardTheme: CardThemeData(
        color: AppColorsDark.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          side: const BorderSide(color: AppColorsDark.border),
        ),
        elevation: 0,
        margin: const EdgeInsets.all(AppSizes.gap),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColorsDark.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColorsDark.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColorsDark.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide:
              const BorderSide(color: AppColorsDark.primary, width: 2),
        ),
        hintStyle: const TextStyle(color: AppColorsDark.muted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColorsDark.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColorsDark.text,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          side: const BorderSide(color: AppColorsDark.border),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColorsDark.surface,
        contentTextStyle: TextStyle(color: AppColorsDark.text),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColorsDark.surface,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColorsDark.surface,
      ),
    );
  }
}
