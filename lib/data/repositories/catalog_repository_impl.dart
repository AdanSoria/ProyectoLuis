import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../core/db/app_database.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/catalog_item.dart';
import '../../domain/entities/sync_queue.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../models/catalog_item_model.dart';
import '../models/sync_queue_model.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._db, this._ids);

  final AppDatabase _db;
  final IdGenerator _ids;

  @override
  Future<List<CatalogItem>> getAll({bool includeInactive = false}) async {
    final rows = await _db.db.query(
      'catalogo',
      where: includeInactive ? null : 'activo = 1',
      orderBy: 'categoria ASC, nombre ASC',
    );
    return [for (final row in rows) CatalogItemModel.fromRow(row)];
  }

  @override
  Future<CatalogItem?> getById(String id) async {
    final rows = await _db.db
        .query('catalogo', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : CatalogItemModel.fromRow(rows.first);
  }

  @override
  Future<Result<CatalogItem>> save(
    CatalogItem item, {
    required bool isNew,
  }) async {
    try {
      await _db.db.transaction((txn) async {
        await txn.insert(
          'catalogo',
          CatalogItemModel.toRow(item),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await SyncQueueModel.enqueue(
          txn,
          SyncQueueEntry(
            id: _ids.newId(),
            entityType: 'catalogo',
            entityId: item.id,
            operation:
                isNew ? SyncOperationType.create : SyncOperationType.update,
            payload: CatalogItemModel.toSyncJson(item),
            createdAt: item.updatedAt,
          ),
        );
      });
      return Ok(item);
    } on Exception catch (e) {
      return Err(DatabaseFailure('No se pudo guardar el artículo: $e'));
    }
  }

  @override
  Future<Result<void>> adjustStock({
    required String productId,
    required double delta,
    required String reason,
  }) async {
    try {
      late Result<void> outcome;

      await _db.db.transaction((txn) async {
        final rows = await txn.query(
          'catalogo',
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (rows.isEmpty) {
          outcome = const Err(NotFoundFailure('El producto no existe.'));
          return;
        }

        final item = CatalogItemModel.fromRow(rows.first);
        if (item is! Product) {
          outcome = const Err(
              ValidationFailure('Los servicios no manejan existencias.'));
          return;
        }

        final newStock = item.stock + delta;
        if (newStock < 0) {
          outcome = Err(InsufficientStockFailure(item.name, item.stock));
          return;
        }

        final now = DateTime.now().toUtc();
        final updated = item.copyWith(stock: newStock, updatedAt: now);

        await txn.update(
          'catalogo',
          CatalogItemModel.toRow(updated),
          where: 'id = ?',
          whereArgs: [productId],
        );
        await txn.insert('movimientos_inventario', {
          'id': _ids.newId(),
          'item_id': productId,
          'delta': delta,
          'motivo': reason,
          'transaccion_id': null,
          'creado_en': now.toIso8601String(),
        });
        await SyncQueueModel.enqueue(
          txn,
          SyncQueueEntry(
            id: _ids.newId(),
            entityType: 'catalogo',
            entityId: productId,
            operation: SyncOperationType.update,
            payload: CatalogItemModel.toSyncJson(updated),
            createdAt: now,
          ),
        );

        outcome = const Ok(null);
      });

      return outcome;
    } on Exception catch (e) {
      return Err(DatabaseFailure('No se pudo ajustar el inventario: $e'));
    }
  }
}
