/// Folio corto legible para humanos, derivado del UUID y la fecha.
/// El UUID sigue siendo la llave real; el folio solo facilita hablar
/// de una venta por teléfono o en un ticket impreso. Ej: `260610-3F2A`.
class Folio {
  Folio._();

  static String fromUuid(String uuid, DateTime date) {
    final yy = (date.year % 100).toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final tail = uuid.replaceAll('-', '').substring(0, 4).toUpperCase();
    return '$yy$mm$dd-$tail';
  }
}
