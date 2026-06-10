import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../core/db/app_database.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/delivery_person.dart';
import '../../domain/entities/sync_queue.dart';
import '../../domain/repositories/delivery_repository.dart';
import '../models/delivery_person_model.dart';
import '../models/sync_queue_model.dart';

class DeliveryRepositoryImpl implements DeliveryRepository {
  DeliveryRepositoryImpl(this._db, this._ids);

  final AppDatabase _db;
  final IdGenerator _ids;

  @override
  Future<List<DeliveryPerson>> getActive() async {
    final rows = await _db.db
        .query('repartidores', where: 'activo = 1', orderBy: 'nombre ASC');
    return [for (final row in rows) DeliveryPersonModel.fromRow(row)];
  }

  @override
  Future<Result<DeliveryPerson>> save(
    DeliveryPerson person, {
    required bool isNew,
  }) async {
    try {
      await _db.db.transaction((txn) async {
        await txn.insert(
          'repartidores',
          DeliveryPersonModel.toRow(person),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await SyncQueueModel.enqueue(
          txn,
          SyncQueueEntry(
            id: _ids.newId(),
            entityType: 'repartidor',
            entityId: person.id,
            operation:
                isNew ? SyncOperationType.create : SyncOperationType.update,
            payload: DeliveryPersonModel.toSyncJson(person),
            createdAt: DateTime.now().toUtc(),
          ),
        );
      });
      return Ok(person);
    } on Exception catch (e) {
      return Err(DatabaseFailure('No se pudo guardar el repartidor: $e'));
    }
  }
}
