import '../../core/db/app_database.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/sync_queue.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../models/sync_queue_model.dart';
import '../models/transaction_model.dart';

/// Implementación SQLite. Toda mutación ocurre dentro de UNA transacción
/// de base de datos: venta + stock + movimientos + Outbox, todo o nada.
class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl(this._db, this._ids);

  final AppDatabase _db;
  final IdGenerator _ids;

  @override
  Future<Result<Transaction>> processNew(Transaction transaction) async {
    try {
      late Result<Transaction> outcome;

      await _db.db.transaction((txn) async {
        // 1. Validar existencias de las líneas de producto.
        for (final line in transaction.lines.where((l) => !l.isService)) {
          final rows = await txn.query(
            'catalogo',
            columns: ['stock', 'nombre'],
            where: 'id = ?',
            whereArgs: [line.itemId],
            limit: 1,
          );
          if (rows.isEmpty) {
            outcome = Err(NotFoundFailure(
                'El producto "${line.itemName}" ya no está en el catálogo.'));
            return;
          }
          final available = (rows.first['stock'] as num?)?.toDouble() ?? 0;
          if (available < line.quantity) {
            outcome = Err(InsufficientStockFailure(line.itemName, available));
            return;
          }
        }

        final nowIso = transaction.createdAt.toIso8601String();

        // 2. Descontar inventario y registrar el movimiento (solo productos;
        //    los servicios se cobran sin tocar stock).
        for (final line in transaction.lines.where((l) => !l.isService)) {
          await txn.rawUpdate(
            'UPDATE catalogo SET stock = stock - ?, actualizado_en = ? WHERE id = ?',
            [line.quantity, nowIso, line.itemId],
          );
          await txn.insert('movimientos_inventario', {
            'id': _ids.newId(),
            'item_id': line.itemId,
            'delta': -line.quantity,
            'motivo': transaction.kind.code,
            'transaccion_id': transaction.id,
            'creado_en': nowIso,
          });
        }

        // 3. Insertar cabecera y líneas.
        await txn.insert('transacciones', TransactionModel.toRow(transaction));
        for (final line in transaction.lines) {
          await txn.insert('transaccion_lineas',
              TransactionModel.lineToRow(transaction.id, line));
        }

        // 4. Encolar en el Outbox (misma transacción SQLite = atómico).
        await SyncQueueModel.enqueue(
          txn,
          SyncQueueEntry(
            id: _ids.newId(),
            entityType: 'transaccion',
            entityId: transaction.id,
            operation: SyncOperationType.create,
            payload: TransactionModel.toSyncJson(transaction),
            createdAt: transaction.createdAt,
          ),
        );

        outcome = Ok(transaction);
      });

      return outcome;
    } on Exception catch (e) {
      return Err(DatabaseFailure('No se pudo guardar la operación: $e'));
    }
  }

  @override
  Future<Result<Transaction>> update(
    Transaction transaction, {
    bool restock = false,
  }) async {
    try {
      await _db.db.transaction((txn) async {
        final nowIso = transaction.updatedAt.toIso8601String();

        await txn.update(
          'transacciones',
          TransactionModel.toRow(transaction),
          where: 'id = ?',
          whereArgs: [transaction.id],
        );

        // Cancelación: devolver existencias de productos al inventario.
        if (restock) {
          for (final line in transaction.lines.where((l) => !l.isService)) {
            await txn.rawUpdate(
              'UPDATE catalogo SET stock = stock + ?, actualizado_en = ? WHERE id = ?',
              [line.quantity, nowIso, line.itemId],
            );
            await txn.insert('movimientos_inventario', {
              'id': _ids.newId(),
              'item_id': line.itemId,
              'delta': line.quantity,
              'motivo': 'cancelacion',
              'transaccion_id': transaction.id,
              'creado_en': nowIso,
            });
          }
        }

        await SyncQueueModel.enqueue(
          txn,
          SyncQueueEntry(
            id: _ids.newId(),
            entityType: 'transaccion',
            entityId: transaction.id,
            operation: SyncOperationType.update,
            payload: TransactionModel.toSyncJson(transaction),
            createdAt: transaction.updatedAt,
          ),
        );
      });

      return Ok(transaction);
    } on Exception catch (e) {
      return Err(DatabaseFailure('No se pudo actualizar el pedido: $e'));
    }
  }

  @override
  Future<Transaction?> getById(String id) async {
    final rows = await _db.db
        .query('transacciones', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;

    final lines = await _db.db.query(
      'transaccion_lineas',
      where: 'transaccion_id = ?',
      whereArgs: [id],
    );
    return TransactionModel.fromRows(rows.first, lines);
  }

  @override
  Future<List<Transaction>> getOrders({OrderStatus? status}) {
    final where = StringBuffer('tipo = ?');
    final args = <Object?>[TransactionKind.pedido.code];
    if (status != null) {
      where.write(' AND estado = ?');
      args.add(status.code);
    }
    return _queryWithLines(where.toString(), args);
  }

  @override
  Future<List<Transaction>> getByDateRange(DateTime from, DateTime to) =>
      _queryWithLines(
        'creado_en >= ? AND creado_en < ?',
        [from.toIso8601String(), to.toIso8601String()],
      );

  @override
  Future<int> countOrders({required List<OrderStatus> statuses}) async {
    final placeholders = List.filled(statuses.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT COUNT(*) AS n FROM transacciones '
      'WHERE tipo = ? AND estado IN ($placeholders)',
      [TransactionKind.pedido.code, ...statuses.map((s) => s.code)],
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Carga cabeceras + todas sus líneas en dos consultas (sin N+1).
  Future<List<Transaction>> _queryWithLines(
    String where,
    List<Object?> args,
  ) async {
    final headers = await _db.db.query(
      'transacciones',
      where: where,
      whereArgs: args,
      orderBy: 'creado_en DESC',
    );
    if (headers.isEmpty) return const [];

    final ids = headers.map((h) => h['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final lineRows = await _db.db.query(
      'transaccion_lineas',
      where: 'transaccion_id IN ($placeholders)',
      whereArgs: ids,
    );

    final linesByTxn = <String, List<Map<String, Object?>>>{};
    for (final row in lineRows) {
      linesByTxn
          .putIfAbsent(row['transaccion_id'] as String, () => [])
          .add(row);
    }

    return [
      for (final header in headers)
        TransactionModel.fromRows(
          header,
          linesByTxn[header['id'] as String] ?? const [],
        ),
    ];
  }
}
