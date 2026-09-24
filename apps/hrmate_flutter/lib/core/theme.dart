import 'package:flutter/material.dart';

/// HRMate design tokens — mirror the web brand (navy ink + emerald/teal emblem).
class HMC {
  static const ink = Color(0xFF0A1628);
  static const inkSoft = Color(0xFF12273F);
  static const emerald = Color(0xFF10D9A0);
  static const emeraldDeep = Color(0xFF059669);
  static const teal = Color(0xFF0F766E);
  static const amber = Color(0xFFF59E0B);
  // semantic aliases (P2 features)
  static const primary = emerald;
  static const primaryDark = emeraldDeep;
  static const primaryFade = Color(0x1A10D9A0);
  static const warn = amber;
  static const warnFade = Color(0x29F59E0B);
  static const bg = Color(0xFFF8FAFC);
  static const danger = Color(0xFFDC2626);

  static const brand = LinearGradient(
    colors: [emerald, teal],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildHmTheme() {
  final base = ThemeData.light(useMaterial3: true);
  final gurmukhiFallback = <String>['Noto Sans Gurmukhi', 'sans-serif'];
  return base.copyWith(
    scaffoldBackgroundColor: HMC.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: HMC.emeraldDeep).copyWith(
      primary: HMC.emeraldDeep,
      onPrimary: Colors.white,
      surface: Colors.white,
      error: HMC.danger,
    ),
    textTheme: base.textTheme.apply(fontFamilyFallback: gurmukhiFallback),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: HMC.emeraldDeep, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: HMC.ink,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
  );
}
