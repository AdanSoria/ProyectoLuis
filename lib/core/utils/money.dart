import 'package:intl/intl.dart';

/// Utilidades de dinero. TODO el dinero del sistema se maneja en
/// **centavos (int)** para evitar errores de redondeo de punto flotante
/// en los cálculos financieros (precio_costo, precio_venta, utilidad).
class Money {
  Money._();

  static final NumberFormat _format = NumberFormat.currency(
    locale: 'es_MX',
    symbol: r'$',
    decimalDigits: 2,
  );

  /// Formatea centavos como moneda legible: 175050 -> `$1,750.50`.
  static String format(int cents) => _format.format(cents / 100);

  /// Convierte texto capturado por el usuario a centavos: `"1750.5"` -> 175050.
  static int fromText(String text) {
    final clean = text.replaceAll(',', '').replaceAll(RegExp(r'[^\d.\-]'), '');
    final value = double.tryParse(clean) ?? 0;
    return (value * 100).round();
  }
}
