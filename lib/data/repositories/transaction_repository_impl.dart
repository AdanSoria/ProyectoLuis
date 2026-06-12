import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../../core/db/app_database.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/insights.dart';
import '../../domain/entities/sync_queue.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../models/sync_queue_model.dart';
import '../models/transaction_model.dart';

/// Implementación SQLite. Toda mutación ocurre dentro de UNA transacción
/// de base de datos: venta + stock por variante + movimientos + historial
/// del cliente + Outbox, todo o nada.
class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl(this._db, this._ids);

  final AppDatabase _db;
  final IdGenerator _ids;

  @override
  Future<Result<Transaction>> processNew(Transaction transaction) async {
    try {
      late Result<Transaction> outcome;

      await _db.db.transaction((txn) async {
        // 1. Validar existencias por VARIANTE (los servicios no aplican).
        //    Para datos previos a variantes, la default usa el id del item.
        for (final line in transaction.lines.where((l) => !l.isService)) {
          final variantId = line.variantId ?? line.itemId;
          final rows = await txn.query(
            'variantes',
            columns: ['stock'],
            where: 'id = ?',
            whereArgs: [variantId],
            limit: 1,
          );
          if (rows.isEmpty) {
            outcome = Err(NotFoundFailure(
                '"${line.itemName}" ya no está en el catálogo.'));
            return;
          }
          final available = (rows.first['stock'] as num?)?.toDouble() ?? 0;
          if (available < line.quantity) {
            outcome = Err(InsufficientStockFailure(line.itemName, available));
            return;
          }
        }

        final nowIso = transaction.createdAt.toIso8601String();

        // 2. Descontar inventario y registrar el movimiento.
        for (final line in transaction.lines.where((l) => !l.isService)) {
          final variantId = line.variantId ?? line.itemId;
          await txn.rawUpdate(
            'UPDATE variantes SET stock = stock - ?, actualizado_en = ? '
            'WHERE id = ?',
            [line.quantity, nowIso, variantId],
          );
          await txn.insert('movimientos_inventario', {
            'id': _ids.newId(),
            'item_id': line.itemId,
            'variante_id': variantId,
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

        // 4. Historial del cliente: solo dinero realmente cobrado.
        if (transaction.status == OrderStatus.completado) {
          await _creditCustomer(txn, transaction);
        }

        // 5. Encolar en el Outbox (misma transacción SQLite = atómico).
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
    bool creditCustomerStats = false,
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

        // Cancelación: devolver existencias a sus variantes.
        if (restock) {
          for (final line in transaction.lines.where((l) => !l.isService)) {
            final variantId = line.variantId ?? line.itemId;
            await txn.rawUpdate(
              'UPDATE variantes SET stock = stock + ?, actualizado_en = ? '
              'WHERE id = ?',
              [line.quantity, nowIso, variantId],
            );
            await txn.insert('movimientos_inventario', {
              'id': _ids.newId(),
              'item_id': line.itemId,
              'variante_id': variantId,
              'delta': line.quantity,
              'motivo': 'cancelacion',
              'transaccion_id': transaction.id,
              'creado_en': nowIso,
            });
          }
        }

        // Pedido entregado y cobrado: acumular historial del cliente.
        if (creditCustomerStats &&
            transaction.status == OrderStatus.completado) {
          await _creditCustomer(txn, transaction);
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

  /// `total_spent`, número de compras y última compra del cliente.
  /// (El servidor puede derivar esto de las transacciones, por eso no
  /// genera una entrada extra en el Outbox.)
  Future<void> _creditCustomer(
    DatabaseExecutor txn,
    Transaction transaction,
  ) async {
    final customerId = transaction.customerId;
    if (customerId == null) return;
    await txn.rawUpdate(
      'UPDATE clientes SET total_gastado = total_gastado + ?, '
      'compras = compras + 1, ultima_compra = ? WHERE id = ?',
      [
        transaction.totalCents,
        transaction.updatedAt.toIso8601String(),
        customerId,
      ],
    );
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

  // ------------------------------------------------ analítica local (SQL)

  @override
  Future<List<TopBuyer>> getTopBuyers({int limit = 10}) async {
    final rows = await _db.db.rawQuery(
      'SELECT cliente_id, cliente_nombre, SUM(total) AS total, '
      'COUNT(*) AS compras FROM transacciones '
      "WHERE estado = 'completado' AND cliente_id IS NOT NULL "
      'GROUP BY cliente_id ORDER BY total DESC LIMIT ?',
      [limit],
    );
    return [
      for (final row in rows)
        TopBuyer(
          customerId: row['cliente_id'] as String,
          name: (row['cliente_nombre'] as String?) ?? 'Cliente',
          totalCents: (row['total'] as num?)?.toInt() ?? 0,
          purchases: (row['compras'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  @override
  Future<List<ChannelSales>> getSalesByChannel() async {
    final rows = await _db.db.rawQuery(
      'SELECT canal, SUM(total) AS total, COUNT(*) AS n FROM transacciones '
      "WHERE estado = 'completado' GROUP BY canal ORDER BY total DESC",
    );
    return [
      for (final row in rows)
        ChannelSales(
          channelCode: row['canal'] as String,
          totalCents: (row['total'] as num?)?.toInt() ?? 0,
          count: (row['n'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  @override
  Future<List<CategorySales>> getTopCategories({int limit = 8}) async {
    final rows = await _db.db.rawQuery(
      'SELECT c.categoria AS categoria, SUM(l.importe) AS total, '
      'SUM(l.cantidad) AS cantidad '
      'FROM transaccion_lineas l '
      'JOIN transacciones t ON t.id = l.transaccion_id '
      'JOIN catalogo c ON c.id = l.item_id '
      "WHERE t.estado = 'completado' "
      'GROUP BY c.categoria ORDER BY total DESC LIMIT ?',
      [limit],
    );
    return [
      for (final row in rows)
        CategorySales(
          category: row['categoria'] as String,
          totalCents: (row['total'] as num?)?.toInt() ?? 0,
          quantity: (row['cantidad'] as num?)?.toDouble() ?? 0,
        ),
    ];
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
