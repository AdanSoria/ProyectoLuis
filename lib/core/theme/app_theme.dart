import 'package:flutter/material.dart';

/// Tema visual: verde agro, Material 3, densidad cómoda para uso
/// con dedos en mostrador y con mouse en escritorio.
class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF2E7D32);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.comfortable,
      appBarTheme: const AppBarTheme(centerTitle: false),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        isDense: true,
      ),
    );
  }
}
