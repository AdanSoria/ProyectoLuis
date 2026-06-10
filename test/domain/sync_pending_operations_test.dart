import 'package:agropos/core/errors/failures.dart';
import 'package:agropos/core/utils/result.dart';
import 'package:agropos/domain/entities/sync_queue.dart';
import 'package:agropos/domain/repositories/sync_gateway.dart';
import 'package:agropos/domain/repositories/sync_queue_repository.dart';
import 'package:agropos/domain/usecases/sync_pending_operations_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeQueue implements SyncQueueRepository {
  _FakeQueue(this.entries);

  List<SyncQueueEntry> entries;
  final completed = <String>[];
  final failed = <(String, String)>[];

  @override
  Future<int> pendingCount() async => entries.length;

  @override
  Future<List<SyncQueueEntry>> takeBatch(int limit, {DateTime? now}) async =>
      entries.take(limit).toList();

  @override
  Future<void> markCompleted(List<String> entryIds) async {
    completed.addAll(entryIds);
    entries.removeWhere((e) => entryIds.contains(e.id));
  }

  @override
  Future<void> markFailed(String entryId, String error, {DateTime? now}) async {
    failed.add((entryId, error));
    entries.removeWhere((e) => e.id == entryId);
  }

  @override
  Future<void> resetInFlight() async {}

  @override
  Future<void> retryErrored() async {}
}

class _FakeGateway implements SyncGateway {
  _FakeGateway(this.handler);

  final Future<Result<List<SyncOpResult>>> Function(
      String deviceId, List<SyncQueueEntry> entries) handler;

  String? lastDeviceId;
  List<SyncQueueEntry>? lastEntries;

  @override
  Future<Result<List<SyncOpResult>>> sendBatch({
    required String deviceId,
    required List<SyncQueueEntry> entries,
  }) {
    lastDeviceId = deviceId;
    lastEntries = entries;
    return handler(deviceId, entries);
  }
}

void main() {
  final t0 = DateTime.utc(2026, 6, 10, 17);

  SyncQueueEntry entry(String id) => SyncQueueEntry(
        id: id,
        entityType: 'transaccion',
        entityId: 'txn-$id',
        operation: SyncOperationType.create,
        payload: {'total': 95000},
        createdAt: t0,
      );

  test('cola vacía: reporta sin trabajo y no llama al gateway', () async {
    final queue = _FakeQueue([]);
    final gateway = _FakeGateway((_, __) async => const Ok([]));
    final useCase = SyncPendingOperationsUseCase(
        queue: queue, gateway: gateway, now: () => t0);

    final result = await useCase(deviceId: 'dev-1');

    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.hadWork, isFalse);
    expect(gateway.lastEntries, isNull);
  });

  test('lote aceptado completo: las entradas salen de la cola', () async {
    final queue = _FakeQueue([entry('a'), entry('b')]);
    final gateway = _FakeGateway((_, entries) async => Ok([
          for (final e in entries) SyncOpResult(entryId: e.id, ok: true),
        ]));
    final useCase = SyncPendingOperationsUseCase(
        queue: queue, gateway: gateway, now: () => t0);

    final result = await useCase(deviceId: 'dev-1');

    expect(gateway.lastDeviceId, 'dev-1');
    final report = result.valueOrNull!;
    expect(report.sent, 2);
    expect(report.succeeded, 2);
    expect(report.failed, 0);
    expect(report.remaining, 0);
    expect(queue.completed, ['a', 'b']);
    expect(queue.failed, isEmpty);
  });

  test('rechazo parcial: solo la operación rechazada reintenta', () async {
    final queue = _FakeQueue([entry('a'), entry('b')]);
    final gateway = _FakeGateway((_, __) async => const Ok([
          SyncOpResult(entryId: 'a', ok: true),
          SyncOpResult(entryId: 'b', ok: false, message: 'payload inválido'),
        ]));
    final useCase = SyncPendingOperationsUseCase(
        queue: queue, gateway: gateway, now: () => t0);

    final result = await useCase(deviceId: 'dev-1');

    final report = result.valueOrNull!;
    expect(report.succeeded, 1);
    expect(report.failed, 1);
    expect(queue.completed, ['a']);
    expect(queue.failed.single.$1, 'b');
    expect(queue.failed.single.$2, 'payload inválido');
  });

  test('falla total de red: todo el lote reintenta con backoff', () async {
    final queue = _FakeQueue([entry('a'), entry('b')]);
    final gateway = _FakeGateway(
        (_, __) async => const Err(NetworkFailure('sin conexión')));
    final useCase = SyncPendingOperationsUseCase(
        queue: queue, gateway: gateway, now: () => t0);

    final result = await useCase(deviceId: 'dev-1');

    expect(result.failureOrNull, isA<NetworkFailure>());
    expect(queue.completed, isEmpty);
    expect(queue.failed, hasLength(2));
  });

  test('backoff exponencial con tope de 30 minutos', () {
    expect(SyncQueueEntry.backoffMinutes(0), 1);
    expect(SyncQueueEntry.backoffMinutes(1), 2);
    expect(SyncQueueEntry.backoffMinutes(3), 8);
    expect(SyncQueueEntry.backoffMinutes(10), 30);
    expect(SyncQueueEntry.backoffMinutes(99), 30);
  });
}
