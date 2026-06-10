import '../../core/utils/result.dart';
import '../entities/sync_queue.dart';

/// Resultado individual reportado por el servidor para una operación.
class SyncOpResult {
  const SyncOpResult({required this.entryId, required this.ok, this.message});

  final String entryId;
  final bool ok;
  final String? message;
}

/// Puerto de salida hacia la API central. El dominio no sabe si detrás
/// hay Laravel, Node o un mock de pruebas: solo conoce este contrato.
abstract class SyncGateway {
  /// Envía un lote del Outbox. [Err] = falla total (red caída, HTTP 500);
  /// [Ok] = el servidor respondió, con el veredicto de cada operación.
  Future<Result<List<SyncOpResult>>> sendBatch({
    required String deviceId,
    required List<SyncQueueEntry> entries,
  });
}
