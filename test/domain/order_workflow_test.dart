import 'package:agropos/core/errors/failures.dart';
import 'package:agropos/core/utils/result.dart';
import 'package:agropos/domain/entities/delivery_person.dart';
import 'package:agropos/domain/entities/insights.dart';
import 'package:agropos/domain/entities/transaction.dart';
import 'package:agropos/domain/repositories/transaction_repository.dart';
import 'package:agropos/domain/usecases/assign_order_usecase.dart';
import 'package:agropos/domain/usecases/cancel_order_usecase.dart';
import 'package:agropos/domain/usecases/complete_order_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransactionRepository implements TransactionRepository {
  Transaction? stored;
  Transaction? updated;
  bool? restockFlag;
  bool? creditFlag;

  @override
  Future<Transaction?> getById(String id) async => stored;

  @override
  Future<Result<Transaction>> update(Transaction transaction,
      {bool restock = false, bool creditCustomerStats = false}) async {
    updated = transaction;
    restockFlag = restock;
    creditFlag = creditCustomerStats;
    return Ok(transaction);
  }

  @override
  Future<Result<Transaction>> processNew(Transaction transaction) async =>
      Ok(transaction);

  @override
  Future<List<Transaction>> getOrders({OrderStatus? status}) async => const [];

  @override
  Future<List<Transaction>> getByDateRange(DateTime from, DateTime to) async =>
      const [];

  @override
  Future<int> countOrders({required List<OrderStatus> statuses}) async => 0;

  @override
  Future<List<TopBuyer>> getTopBuyers({int limit = 10}) async => const [];

  @override
  Future<List<ChannelSales>> getSalesByChannel() async => const [];

  @override
  Future<List<CategorySales>> getTopCategories({int limit = 8}) async =>
      const [];
}

void main() {
  final t0 = DateTime.utc(2026, 6, 10, 16);
  const courier = DeliveryPerson(id: 'rep-1', name: 'Repartidor moto');

  Transaction order(OrderStatus status,
          {TransactionKind kind = TransactionKind.pedido}) =>
      Transaction(
        id: 'txn-1',
        folio: '260610-AAAA',
        kind: kind,
        channel: SaleChannel.whatsapp,
        status: status,
        customerName: 'Rancho El Mezquite',
        lines: [
          const TransactionLine(
            id: 'l1',
            itemId: 'prod-1',
            itemName: 'Alimento para becerro',
            isService: false,
            quantity: 2,
            unitPriceCents: 64000,
            unitCostCents: 52000,
          ),
        ],
        createdAt: t0,
        updatedAt: t0,
      );

  late _FakeTransactionRepository repository;

  setUp(() => repository = _FakeTransactionRepository());

  group('AssignOrderUseCase', () {
    test('pendiente -> asignado', () async {
      repository.stored = order(OrderStatus.pendiente);
      final useCase =
          AssignOrderUseCase(transactions: repository, now: () => t0);

      final result =
          await useCase(orderId: 'txn-1', deliveryPerson: courier);

      expect(result.isOk, isTrue);
      expect(repository.updated!.status, OrderStatus.asignado);
      expect(repository.updated!.deliveryPersonId, 'rep-1');
      expect(repository.updated!.deliveryPersonName, 'Repartidor moto');
    });

    test('no se puede asignar un pedido completado', () async {
      repository.stored = order(OrderStatus.completado);
      final useCase =
          AssignOrderUseCase(transactions: repository, now: () => t0);

      final result =
          await useCase(orderId: 'txn-1', deliveryPerson: courier);

      expect(result.failureOrNull, isA<InvalidTransitionFailure>());
      expect(repository.updated, isNull);
    });

    test('una venta de mostrador no entra al flujo de reparto', () async {
      repository.stored = order(OrderStatus.completado,
          kind: TransactionKind.ventaMostrador);
      final useCase =
          AssignOrderUseCase(transactions: repository, now: () => t0);

      final result =
          await useCase(orderId: 'txn-1', deliveryPerson: courier);

      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('pedido inexistente', () async {
      final useCase =
          AssignOrderUseCase(transactions: repository, now: () => t0);

      final result =
          await useCase(orderId: 'no-existe', deliveryPerson: courier);

      expect(result.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('CompleteOrderUseCase', () {
    test('asignado -> completado registra el cobro total', () async {
      repository.stored = order(OrderStatus.asignado);
      final useCase =
          CompleteOrderUseCase(transactions: repository, now: () => t0);

      final result = await useCase(
          orderId: 'txn-1', paymentMethod: PaymentMethod.efectivo);

      expect(result.isOk, isTrue);
      expect(repository.updated!.status, OrderStatus.completado);
      expect(repository.updated!.paymentMethod, PaymentMethod.efectivo);
      expect(repository.updated!.amountPaidCents,
          repository.updated!.totalCents);
      // Al cobrar se acredita el historial del cliente (total_spent).
      expect(repository.creditFlag, isTrue);
    });

    test('pendiente no puede saltar a completado', () async {
      repository.stored = order(OrderStatus.pendiente);
      final useCase =
          CompleteOrderUseCase(transactions: repository, now: () => t0);

      final result = await useCase(orderId: 'txn-1');

      expect(result.failureOrNull, isA<InvalidTransitionFailure>());
    });
  });

  group('CancelOrderUseCase', () {
    test('cancelar pide reposición de stock al repositorio', () async {
      repository.stored = order(OrderStatus.asignado);
      final useCase =
          CancelOrderUseCase(transactions: repository, now: () => t0);

      final result = await useCase(orderId: 'txn-1');

      expect(result.isOk, isTrue);
      expect(repository.updated!.status, OrderStatus.cancelado);
      expect(repository.restockFlag, isTrue);
    });

    test('un pedido completado ya no se cancela', () async {
      repository.stored = order(OrderStatus.completado);
      final useCase =
          CancelOrderUseCase(transactions: repository, now: () => t0);

      final result = await useCase(orderId: 'txn-1');

      expect(result.failureOrNull, isA<InvalidTransitionFailure>());
    });
  });
}
