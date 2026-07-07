/// Configuración global de la aplicación.
///
/// Mantiene el proyecto agnóstico: la URL del backend se inyecta en tiempo
/// de compilación y puede apuntar a cualquier API REST (Laravel, Node, etc.):
///
/// ```bash
/// flutter run --dart-define=AGROPOS_API_URL=https://mi-servidor.com
/// ```
class AppConfig {
  AppConfig._();

  /// Nombre visible de la aplicación (marca del negocio).
  static const String appName = 'El Alazán';

  /// Subtítulo de la marca.
  static const String appTagline = 'Agroalimentos';

  /// URL base de la API central. Vacía = modo 100% local
  /// (la cola de sincronización acumula operaciones hasta configurarla).
  static const String apiBaseUrl = String.fromEnvironment(
    'AGROPOS_API_URL',
    defaultValue: '',
  );

  /// Tamaño de lote para el envío de la cola de sincronización (batching).
  static const int syncBatchSize = 25;

  /// Intervalo del intento de sincronización silenciosa en segundo plano.
  static const Duration syncInterval = Duration(minutes: 2);

  /// Intentos máximos antes de marcar una operación como `error`
  /// (requiere reintento manual desde el panel de sincronización).
  static const int syncMaxAttempts = 8;

  /// Umbral para resaltar productos con stock bajo en el inventario.
  static const double lowStockThreshold = 5;

  /// Unidades **inequívocamente a granel**: un toque abre directamente la
  /// hoja de captura de cantidad en vez de "1 toque = 1 pieza". Se dejan
  /// fuera unidades ambiguas como `litro`/`metro` (suelen ser una
  /// presentación de pieza: botella de 1 L, rollo) — esas siguen abriendo
  /// la hoja con long-press o cuando el producto tiene varias variantes,
  /// y conservan sus atajos en [bulkQuantityShortcuts].
  static const Set<String> weightVolumeUnits = {
    'kg', 'kilo', 'kilos', 'g', 'gramo', 'gramos', 'granel',
  };

  /// Atajos de cantidad para granel, por unidad. Se usan cuando la variante
  /// es unitaria (`contentUnits == 1`) y no hay una presentación mayor de
  /// referencia en el mismo producto. La llave `'default'` cubre el resto.
  static const Map<String, List<double>> bulkQuantityShortcuts = {
    'kg': [1, 5, 10, 25, 50],
    'kilo': [1, 5, 10, 25, 50],
    'g': [100, 250, 500, 1000],
    'gramo': [100, 250, 500, 1000],
    'litro': [1, 5, 10, 20],
    'lt': [1, 5, 10, 20],
    'l': [1, 5, 10, 20],
    'ml': [250, 500, 1000],
    'metro': [1, 5, 10, 50],
    'm': [1, 5, 10, 50],
    'default': [1, 5, 10, 25],
  };

  /// ¿La unidad se vende por peso/volumen? (insensible a mayúsculas).
  static bool isWeightVolume(String unit) =>
      weightVolumeUnits.contains(unit.trim().toLowerCase());

  /// Atajos de cantidad para una unidad de granel (cae a `default`).
  static List<double> bulkShortcutsFor(String unit) =>
      bulkQuantityShortcuts[unit.trim().toLowerCase()] ??
      bulkQuantityShortcuts['default']!;

  /// Punto de quiebre de diseño: a partir de este ancho se usa el
  /// modo mostrador de pantalla dividida (catálogo + ticket).
  static const double splitScreenBreakpoint = 840;

  /// Punto de quiebre para usar barra de navegación lateral (escritorio).
  static const double railBreakpoint = 900;
}
