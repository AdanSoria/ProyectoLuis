import '../../core/config/app_config.dart';
import '../../core/db/app_database.dart';
import '../../domain/entities/sync_queue.dart';
import '../../domain/repositories/sync_queue_repository.dart';
import '../models/sync_queue_model.dart';

class SyncQueueRepositoryImpl implements SyncQueueRepository {
  SyncQueueRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<int> pendingCount() async {
    final rows =
        await _db.db.rawQuery('SELECT COUNT(*) AS n FROM sync_queue');
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<SyncQueueEntry>> takeBatch(int limit, {DateTime? now}) async {
    final nowIso = (now ?? DateTime.now()).toIso8601String();

    return _db.db.transaction((txn) async {
      final rows = await txn.query(
        'sync_queue',
        where: "estado = 'pendiente' "
            'AND (proximo_intento IS NULL OR proximo_intento <= ?)',
        whereArgs: [nowIso],
        orderBy: 'creado_en ASC',
        limit: limit,
      );
      if (rows.isEmpty) return const <SyncQueueEntry>[];

      final ids = rows.map((r) => r['id'] as String).toList();
      final placeholders = List.filled(ids.length, '?').join(',');
      await txn.rawUpdate(
        "UPDATE sync_queue SET estado = 'enviando' WHERE id IN ($placeholders)",
        ids,
      );

      return [
        for (final row in rows)
          SyncQueueModel.fromRow(row)
              .copyWith(status: SyncEntryStatus.enviando),
      ];
    });
  }

  @override
  Future<void> markCompleted(List<String> entryIds) async {
    if (entryIds.isEmpty) return;
    final placeholders = List.filled(entryIds.length, '?').join(',');
    await _db.db
        .rawDelete('DELETE FROM sync_queue WHERE id IN ($placeholders)', entryIds);
  }

  @override
  Future<void> markFailed(String entryId, String error, {DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final rows = await _db.db.query(
      'sync_queue',
      columns: ['intentos'],
      where: 'id = ?',
      whereArgs: [entryId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final attempts = ((rows.first['intentos'] as num?)?.toInt() ?? 0) + 1;
    final exhausted = attempts >= AppConfig.syncMaxAttempts;
    final nextAttempt = reference
        .add(Duration(minutes: SyncQueueEntry.backoffMinutes(attempts)));

    await _db.db.update(
      'sync_queue',
      {
        'estado': exhausted
            ? SyncEntryStatus.error.code
            : SyncEntryStatus.pendiente.code,
        'intentos': attempts,
        'ultimo_error': error,
        'proximo_intento': nextAttempt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }

  @override
  Future<void> resetInFlight() async {
    await _db.db.rawUpdate(
        "UPDATE sync_queue SET estado = 'pendiente' WHERE estado = 'enviando'");
  }

  @override
  Future<void> retryErrored() async {
    await _db.db.rawUpdate(
        "UPDATE sync_queue SET estado = 'pendiente', intentos = 0, "
        "proximo_intento = NULL WHERE estado = 'error'");
  }
}
