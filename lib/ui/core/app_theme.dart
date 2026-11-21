import 'package:flutter/material.dart';

/// Melow Tic Tac Toe v2.0 visual identity & Material 3 themes.
class AppTheme {
  static const Color darkBackground = Color(0xFF101125);
  static const Color darkSurface = Color(0xFF1B1C38);
  static const Color darkSurfaceHigh = Color(0xFF26284D);
  static const Color purpleAccent = Color(0xFF8B5CF6);
  static const Color cyanAccent = Color(0xFF22D3EE);
  static const Color goldAccent = Color(0xFFFBBF24);

  static const Color lightBackground = Color(0xFFF8FAFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFEEF2FF);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: purpleAccent,
      brightness: Brightness.light,
      primary: const Color(0xFF6D28D9),
      secondary: const Color(0xFF0891B2),
      tertiary: const Color(0xFFD97706),
      surface: lightSurface,
    );
    return _build(scheme, scaffoldBg: lightBackground, cardBg: lightSurface);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: purpleAccent,
      brightness: Brightness.dark,
      primary: purpleAccent,
      secondary: cyanAccent,
      tertiary: goldAccent,
      surface: darkSurface,
    );
    return _build(scheme, scaffoldBg: darkBackground, cardBg: darkSurface);
  }

  static ThemeData _build(
    ColorScheme scheme, {
    required Color scaffoldBg,
    required Color cardBg,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardBg,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: isDark
                ? purpleAccent.withValues(alpha: 0.24)
                : scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? darkSurface : lightSurface,
        indicatorColor: isDark
            ? purpleAccent.withValues(alpha: 0.25)
            : purpleAccent.withValues(alpha: 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? darkSurfaceHigh.withValues(alpha: 0.7)
            : lightSurfaceHigh.withValues(alpha: 0.65),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark
                ? purpleAccent.withValues(alpha: 0.28)
                : scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 46),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
