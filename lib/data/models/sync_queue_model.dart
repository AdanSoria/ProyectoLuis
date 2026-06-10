import 'dart:convert';

import 'package:sqflite/sqflite.dart' as sql;

import '../../domain/entities/sync_queue.dart';

class SyncQueueModel {
  SyncQueueModel._();

  static Map<String, Object?> toRow(SyncQueueEntry e) => {
        'id': e.id,
        'entidad': e.entityType,
        'entidad_id': e.entityId,
        'operacion': e.operation.code,
        'payload': jsonEncode(e.payload),
        'estado': e.status.code,
        'intentos': e.attempts,
        'ultimo_error': e.lastError,
        'proximo_intento': e.nextAttemptAt?.toIso8601String(),
        'creado_en': e.createdAt.toIso8601String(),
      };

  static SyncQueueEntry fromRow(Map<String, Object?> row) => SyncQueueEntry(
        id: row['id'] as String,
        entityType: row['entidad'] as String,
        entityId: row['entidad_id'] as String,
        operation: SyncOperationType.fromCode(row['operacion'] as String),
        payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        status: SyncEntryStatus.fromCode(row['estado'] as String),
        attempts: (row['intentos'] as num? ?? 0).toInt(),
        lastError: row['ultimo_error'] as String?,
        nextAttemptAt: row['proximo_intento'] == null
            ? null
            : DateTime.parse(row['proximo_intento'] as String),
        createdAt: DateTime.parse(row['creado_en'] as String),
      );

  /// Inserta una entrada del Outbox usando el MISMO executor de la
  /// transacción SQLite en curso — esta es la pieza que hace atómico el
  /// "guardar venta + encolar sincronización".
  static Future<void> enqueue(
    sql.DatabaseExecutor executor,
    SyncQueueEntry entry,
  ) =>
      executor.insert('sync_queue', toRow(entry));
}
