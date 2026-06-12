import 'package:flutter/material.dart';

/// Tema visual de **El Alazán Agroalimentos**: verde profundo y dorado
/// del logotipo, Material 3, densidad cómoda para mostrador y escritorio.
class AppTheme {
  AppTheme._();

  /// Verde profundo del fondo del logotipo.
  static const Color brandGreen = Color(0xFF1E4427);

  /// Dorado del caballo y la tipografía.
  static const Color brandGold = Color(0xFFD9A13B);

  /// Crema del monograma.
  static const Color brandCream = Color(0xFFF4EBD7);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: brandGreen);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.comfortable,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: brandGreen,
        foregroundColor: brandCream,
      ),
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
