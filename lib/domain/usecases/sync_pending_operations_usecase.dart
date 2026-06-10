import '../../core/config/app_config.dart';
import '../../core/utils/result.dart';
import '../repositories/sync_gateway.dart';
import '../repositories/sync_queue_repository.dart';

/// Resumen de un ciclo de sincronización.
class SyncRunReport {
  const SyncRunReport({
    required this.sent,
    required this.succeeded,
    required this.failed,
    required this.remaining,
  });

  final int sent;
  final int succeeded;
  final int failed;

  /// Operaciones que siguen en la cola después del ciclo.
  final int remaining;

  bool get hadWork => sent > 0;
}

/// Toma un lote del Outbox y lo envía al backend (**batching**).
///
/// - Falla total (sin red / HTTP 5xx): todo el lote reintenta con backoff.
/// - Respuesta por operación: las aceptadas se eliminan de la cola y las
///   rechazadas reintentan individualmente.
class SyncPendingOperationsUseCase {
  SyncPendingOperationsUseCase({
    required SyncQueueRepository queue,
    required SyncGateway gateway,
    DateTime Function()? now,
  })  : _queue = queue,
        _gateway = gateway,
        _now = now ?? DateTime.now;

  final SyncQueueRepository _queue;
  final SyncGateway _gateway;
  final DateTime Function() _now;

  Future<Result<SyncRunReport>> call({required String deviceId}) async {
    final batch = await _queue.takeBatch(AppConfig.syncBatchSize, now: _now());
    if (batch.isEmpty) {
      return Ok(SyncRunReport(
        sent: 0,
        succeeded: 0,
        failed: 0,
        remaining: await _queue.pendingCount(),
      ));
    }

    final response =
        await _gateway.sendBatch(deviceId: deviceId, entries: batch);

    switch (response) {
      case Err(:final failure):
        // Falla total: el lote completo regresa a la cola con backoff.
        for (final entry in batch) {
          await _queue.markFailed(entry.id, failure.message, now: _now());
        }
        return Err(failure);

      case Ok(:final value):
        final verdicts = {for (final r in value) r.entryId: r};
        final accepted = <String>[];
        var failed = 0;

        for (final entry in batch) {
          final verdict = verdicts[entry.id];
          // Sin veredicto explícito asumimos aceptada (backends simples
          // que responden 200 sin detalle por operación).
          if (verdict == null || verdict.ok) {
            accepted.add(entry.id);
          } else {
            failed++;
            await _queue.markFailed(
              entry.id,
              verdict.message ?? 'Rechazada por el servidor',
              now: _now(),
            );
          }
        }

        if (accepted.isNotEmpty) {
          await _queue.markCompleted(accepted);
        }

        return Ok(SyncRunReport(
          sent: batch.length,
          succeeded: accepted.length,
          failed: failed,
          remaining: await _queue.pendingCount(),
        ));
    }
  }
}
