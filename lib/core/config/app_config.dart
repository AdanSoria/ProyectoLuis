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

  /// Nombre visible de la aplicación.
  static const String appName = 'AgroPOS';

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

  /// Punto de quiebre de diseño: a partir de este ancho se usa el
  /// modo mostrador de pantalla dividida (catálogo + ticket).
  static const double splitScreenBreakpoint = 840;

  /// Punto de quiebre para usar barra de navegación lateral (escritorio).
  static const double railBreakpoint = 900;
}
