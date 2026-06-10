import '../entities/sync_queue.dart';

abstract class SyncQueueRepository {
  /// Operaciones aún no confirmadas por el servidor (cualquier estado).
  Future<int> pendingCount();

  /// Toma hasta [limit] entradas `pendiente` cuyo backoff ya venció y
  /// las marca `enviando` (evita que dos ciclos tomen el mismo lote).
  Future<List<SyncQueueEntry>> takeBatch(int limit, {DateTime? now});

  /// Confirmadas por el servidor: se eliminan del Outbox.
  Future<void> markCompleted(List<String> entryIds);

  /// Falló el envío: incrementa intentos y agenda el reintento con
  /// backoff; tras demasiados intentos queda en `error` (reintento manual).
  Future<void> markFailed(String entryId, String error, {DateTime? now});

  /// Al arrancar la app, regresa a `pendiente` lo que quedó `enviando`
  /// (la app pudo cerrarse a media sincronización).
  Future<void> resetInFlight();

  /// Reintento manual de las entradas en `error`.
  Future<void> retryErrored();
}
