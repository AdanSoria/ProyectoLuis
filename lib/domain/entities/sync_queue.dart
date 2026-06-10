import 'dart:math' as math;

/// Operación CRUD que viajará al backend.
enum SyncOperationType {
  create('create'),
  update('update');

  const SyncOperationType(this.code);
  final String code;

  static SyncOperationType fromCode(String code) =>
      values.firstWhere((v) => v.code == code);
}

/// Estado de una entrada del Outbox.
enum SyncEntryStatus {
  /// Esperando turno para enviarse.
  pendiente('pendiente'),

  /// Tomada por un lote en vuelo.
  enviando('enviando'),

  /// Rechazada demasiadas veces; requiere reintento manual.
  error('error');

  const SyncEntryStatus(this.code);
  final String code;

  static SyncEntryStatus fromCode(String code) =>
      values.firstWhere((v) => v.code == code);
}

/// Entrada de la Cola de Sincronización (**Outbox Pattern**).
///
/// Cada mutación local (venta, pedido, cambio de estado, alta de catálogo,
/// ajuste de stock) se encola **en la misma transacción SQLite** que la
/// escritura original: si se guardó el dato, se garantizó su envío futuro.
/// Las entradas exitosas se eliminan; las fallidas reintentan con
/// backoff exponencial.
class SyncQueueEntry {
  const SyncQueueEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    this.status = SyncEntryStatus.pendiente,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    required this.createdAt,
  });

  /// UUID v4 de la operación (idempotencia en el servidor).
  final String id;

  /// Entidad afectada: `transaccion`, `catalogo`, `cliente`, `repartidor`...
  final String entityType;

  /// UUID del registro afectado.
  final String entityId;

  final SyncOperationType operation;

  /// Cuerpo completo del registro en JSON (snake_case, agnóstico al backend).
  final Map<String, dynamic> payload;

  final SyncEntryStatus status;
  final int attempts;
  final String? lastError;

  /// No reintentar antes de esta hora (backoff exponencial).
  final DateTime? nextAttemptAt;

  final DateTime createdAt;

  /// Minutos de espera tras el intento número [attempts]: 1, 2, 4, 8... máx 30.
  static int backoffMinutes(int attempts) =>
      math.min(30, 1 << math.min(attempts, 10));

  SyncQueueEntry copyWith({
    SyncEntryStatus? status,
    int? attempts,
    String? lastError,
    DateTime? nextAttemptAt,
  }) =>
      SyncQueueEntry(
        id: id,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        payload: payload,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
        nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
        createdAt: createdAt,
      );
}
