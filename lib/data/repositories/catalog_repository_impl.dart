import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, DatabaseExecutor;

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
    final variantRows = await _db.db.query('variantes');

    final byProduct = <String, List<Map<String, Object?>>>{};
    for (final v in variantRows) {
      byProduct.putIfAbsent(v['producto_id'] as String, () => []).add(v);
    }

    return [
      for (final row in rows)
        CatalogItemModel.fromRow(
          row,
          variantRows: byProduct[row['id'] as String] ?? const [],
        ),
    ];
  }

  @override
  Future<CatalogItem?> getById(String id) async {
    final rows = await _db.db
        .query('catalogo', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;

    final variantRows = await _db.db
        .query('variantes', where: 'producto_id = ?', whereArgs: [id]);
    return CatalogItemModel.fromRow(rows.first, variantRows: variantRows);
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

        if (item is Product) {
          final variants =
              item.variants.isEmpty ? [item.defaultVariant] : item.variants;
          for (final variant in variants) {
            await txn.insert(
              'variantes',
              CatalogItemModel.variantToRow(
                  variant, item.createdAt, item.updatedAt),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

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
    required String variantId,
    required double delta,
    required String reason,
  }) async {
    try {
      late Result<void> outcome;

      await _db.db.transaction((txn) async {
        final rows = await txn.query(
          'variantes',
          where: 'id = ?',
          whereArgs: [variantId],
          limit: 1,
        );
        if (rows.isEmpty) {
          outcome = const Err(NotFoundFailure('La presentación no existe.'));
          return;
        }

        final variant = CatalogItemModel.variantFromRow(rows.first);
        final newStock = variant.stock + delta;
        if (newStock < 0) {
          outcome = Err(InsufficientStockFailure(variant.name, variant.stock));
          return;
        }

        final now = DateTime.now().toUtc();
        await _applyStockChange(txn, variantId, variant.productId, delta,
            reason, null, now.toIso8601String());
        await _enqueueProductSync(txn, variant.productId, now);

        outcome = const Ok(null);
      });

      return outcome;
    } on Exception catch (e) {
      return Err(DatabaseFailure('No se pudo ajustar el inventario: $e'));
    }
  }

  @override
  Future<Result<double>> breakVariant({
    required String sourceVariantId,
    required String targetVariantId,
    required double quantity,
  }) async {
    try {
      late Result<double> outcome;

      await _db.db.transaction((txn) async {
        Future<Map<String, Object?>?> variantRow(String id) async {
          final rows = await txn.query('variantes',
              where: 'id = ?', whereArgs: [id], limit: 1);
          return rows.isEmpty ? null : rows.first;
        }

        final sourceRow = await variantRow(sourceVariantId);
        final targetRow = await variantRow(targetVariantId);
        if (sourceRow == null || targetRow == null) {
          outcome =
              const Err(NotFoundFailure('La presentación ya no existe.'));
          return;
        }

        final source = CatalogItemModel.variantFromRow(sourceRow);
        final target = CatalogItemModel.variantFromRow(targetRow);

        if (source.productId != target.productId) {
          outcome = const Err(ValidationFailure(
              'Las presentaciones no pertenecen al mismo producto.'));
          return;
        }
        if (source.contentUnits <= 0 || target.contentUnits <= 0) {
          outcome = const Err(ValidationFailure(
              'Define el contenido de ambas presentaciones.'));
          return;
        }
        if (source.stock < quantity) {
          outcome = Err(InsufficientStockFailure(source.name, source.stock));
          return;
        }

        // 1 costal de 50 kg (contenido 50) -> 50 unidades de granel kg.
        final credited =
            quantity * source.contentUnits / target.contentUnits;
        final now = DateTime.now().toUtc();
        final nowIso = now.toIso8601String();

        await _applyStockChange(txn, source.id, source.productId, -quantity,
            'desensamble', null, nowIso);
        await _applyStockChange(txn, target.id, target.productId, credited,
            'desensamble', null, nowIso);
        await _enqueueProductSync(txn, source.productId, now);

        outcome = Ok(credited);
      });

      return outcome;
    } on Exception catch (e) {
      return Err(DatabaseFailure('No se pudo fraccionar: $e'));
    }
  }

  // ---------------------------------------------------------- internos

  /// Mueve stock de una variante + registra el movimiento de inventario.
  Future<void> _applyStockChange(
    DatabaseExecutor txn,
    String variantId,
    String productId,
    double delta,
    String reason,
    String? transactionId,
    String nowIso,
  ) async {
    await txn.rawUpdate(
      'UPDATE variantes SET stock = stock + ?, actualizado_en = ? WHERE id = ?',
      [delta, nowIso, variantId],
    );
    await txn.insert('movimientos_inventario', {
      'id': _ids.newId(),
      'item_id': productId,
      'variante_id': variantId,
      'delta': delta,
      'motivo': reason,
      'transaccion_id': transactionId,
      'creado_en': nowIso,
    });
  }

  /// Encola el producto completo (con variantes frescas) en el Outbox,
  /// dentro de la MISMA transacción SQLite en curso.
  Future<void> _enqueueProductSync(
    DatabaseExecutor txn,
    String productId,
    DateTime now,
  ) async {
    final rows = await txn
        .query('catalogo', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (rows.isEmpty) return;
    final variantRows = await txn
        .query('variantes', where: 'producto_id = ?', whereArgs: [productId]);
    final item =
        CatalogItemModel.fromRow(rows.first, variantRows: variantRows);

    await SyncQueueModel.enqueue(
      txn,
      SyncQueueEntry(
        id: _ids.newId(),
        entityType: 'catalogo',
        entityId: productId,
        operation: SyncOperationType.update,
        payload: CatalogItemModel.toSyncJson(item),
        createdAt: now,
      ),
    );
  }
}
