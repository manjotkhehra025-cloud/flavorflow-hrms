import 'package:flutter/material.dart';

/// Clean, professional blue theme (Material 3).
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF1565C0);
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color background = Color(0xFFF4F6FA);

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFEF6C00);
  static const Color danger = Color(0xFFC62828);
  static const Color info = Color(0xFF0277BD);
  static const Color muted = Color(0xFF78909C);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      brightness: Brightness.light,
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48), shape: rounded),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), shape: rounded),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}
