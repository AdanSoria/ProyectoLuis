import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../core/db/app_database.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/sync_queue.dart';
import '../../domain/repositories/customer_repository.dart';
import '../models/customer_model.dart';
import '../models/sync_queue_model.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  CustomerRepositoryImpl(this._db, this._ids);

  final AppDatabase _db;
  final IdGenerator _ids;

  @override
  Future<List<Customer>> getRecent(int limit) async {
    final rows =
        await _db.db.query('clientes', orderBy: 'creado_en DESC', limit: limit);
    return [for (final row in rows) CustomerModel.fromRow(row)];
  }

  @override
  Future<List<Customer>> search(String query) async {
    final rows = await _db.db.query(
      'clientes',
      where: 'nombre LIKE ? OR telefono LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'nombre ASC',
      limit: 20,
    );
    return [for (final row in rows) CustomerModel.fromRow(row)];
  }

  @override
  Future<Result<Customer>> save(Customer customer, {required bool isNew}) async {
    try {
      await _db.db.transaction((txn) async {
        await txn.insert(
          'clientes',
          CustomerModel.toRow(customer),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await SyncQueueModel.enqueue(
          txn,
          SyncQueueEntry(
            id: _ids.newId(),
            entityType: 'cliente',
            entityId: customer.id,
            operation:
                isNew ? SyncOperationType.create : SyncOperationType.update,
            payload: CustomerModel.toSyncJson(customer),
            createdAt: customer.createdAt,
          ),
        );
      });
      return Ok(customer);
    } on Exception catch (e) {
      return Err(DatabaseFailure('No se pudo guardar el cliente: $e'));
    }
  }
}
