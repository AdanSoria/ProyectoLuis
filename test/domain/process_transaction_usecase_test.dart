import 'package:agropos/core/errors/failures.dart';
import 'package:agropos/core/utils/id_generator.dart';
import 'package:agropos/core/utils/result.dart';
import 'package:agropos/domain/entities/cart_line.dart';
import 'package:agropos/domain/entities/catalog_item.dart';
import 'package:agropos/domain/entities/delivery_person.dart';
import 'package:agropos/domain/entities/transaction.dart';
import 'package:agropos/domain/repositories/transaction_repository.dart';
import 'package:agropos/domain/usecases/process_transaction_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransactionRepository implements TransactionRepository {
  Transaction? saved;

  @override
  Future<Result<Transaction>> processNew(Transaction transaction) async {
    saved = transaction;
    return Ok(transaction);
  }

  @override
  Future<Result<Transaction>> update(Transaction transaction,
          {bool restock = false}) async =>
      Ok(transaction);

  @override
  Future<Transaction?> getById(String id) async => null;

  @override
  Future<List<Transaction>> getOrders({OrderStatus? status}) async => const [];

  @override
  Future<List<Transaction>> getByDateRange(DateTime from, DateTime to) async =>
      const [];

  @override
  Future<int> countOrders({required List<OrderStatus> statuses}) async => 0;
}

class _SequentialIds implements IdGenerator {
  int _counter = 0;

  @override
  String newId() => 'uuid-${++_counter}';
}

void main() {
  final t0 = DateTime.utc(2026, 6, 10, 15, 30);

  Product product({int sale = 95000, int cost = 78000, double stock = 10}) =>
      Product(
        id: 'prod-1',
        name: 'Fertilizante',
        category: 'Fertilizantes',
        costPriceCents: cost,
        salePriceCents: sale,
        createdAt: t0,
        updatedAt: t0,
        stock: stock,
      );

  Service service({int sale = 15000, int cost = 6000}) => Service(
        id: 'serv-1',
        name: 'Flete local',
        category: 'Servicios',
        costPriceCents: cost,
        salePriceCents: sale,
        createdAt: t0,
        updatedAt: t0,
      );

  late _FakeTransactionRepository repository;
  late ProcessTransactionUseCase useCase;

  setUp(() {
    repository = _FakeTransactionRepository();
    useCase = ProcessTransactionUseCase(
      transactions: repository,
      idGenerator: _SequentialIds(),
      now: () => t0,
    );
  });

  test('rechaza el carrito vacío', () async {
    final result = await useCase(const ProcessTransactionInput(
      lines: [],
      kind: TransactionKind.ventaMostrador,
    ));

    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(repository.saved, isNull);
  });

  test('rechaza efectivo insuficiente en mostrador', () async {
    final result = await useCase(ProcessTransactionInput(
      lines: [CartLine(item: product(), quantity: 1)],
      kind: TransactionKind.ventaMostrador,
      amountPaidCents: 90000, // total es 95000
    ));

    expect(result.failureOrNull, isA<ValidationFailure>());
  });

  test('venta de mostrador: nace completada con UUID, folio y finanzas',
      () async {
    final result = await useCase(ProcessTransactionInput(
      lines: [
        CartLine(item: product(), quantity: 2),
        CartLine(item: service(), quantity: 1),
      ],
      kind: TransactionKind.ventaMostrador,
      amountPaidCents: 250000,
      deductionsCents: 5000,
    ));

    expect(result.isOk, isTrue);
    final txn = repository.saved!;

    expect(txn.id, 'uuid-1'); // UUID generado en cliente
    expect(txn.folio, isNotEmpty);
    expect(txn.status, OrderStatus.completado);
    expect(txn.kind, TransactionKind.ventaMostrador);

    // Snapshot de precios congelado en las líneas.
    expect(txn.lines, hasLength(2));
    expect(txn.lines.first.unitPriceCents, 95000);
    expect(txn.lines.first.unitCostCents, 78000);
    expect(txn.lines.last.isService, isTrue);

    // precio_costo, precio_venta, deducciones y utilidad_neta.
    expect(txn.subtotalCents, 205000);
    expect(txn.totalCents, 200000);
    expect(txn.costTotalCents, 162000);
    expect(txn.netProfitCents, 38000);
    expect(txn.changeCents, 50000);
  });

  test('un pedido exige nombre de cliente', () async {
    final result = await useCase(ProcessTransactionInput(
      lines: [CartLine(item: product(), quantity: 1)],
      kind: TransactionKind.pedido,
      channel: SaleChannel.whatsapp,
    ));

    expect(result.failureOrNull, isA<ValidationFailure>());
  });

  test('pedido con repartidor nace asignado y por cobrar', () async {
    final result = await useCase(ProcessTransactionInput(
      lines: [CartLine(item: product(), quantity: 1)],
      kind: TransactionKind.pedido,
      channel: SaleChannel.whatsapp,
      customerName: 'Rancho La Loma',
      customerPhone: '5551112233',
      deliveryPerson: const DeliveryPerson(id: 'rep-1', name: 'Repartidor moto'),
    ));

    expect(result.isOk, isTrue);
    final order = repository.saved!;
    expect(order.status, OrderStatus.asignado);
    expect(order.deliveryPersonId, 'rep-1');
    expect(order.paymentMethod, PaymentMethod.porCobrar);
    expect(order.amountPaidCents, 0);
    expect(order.customerName, 'Rancho La Loma');
  });

  test('pedido sin repartidor queda pendiente', () async {
    final result = await useCase(ProcessTransactionInput(
      lines: [CartLine(item: product(), quantity: 1)],
      kind: TransactionKind.pedido,
      channel: SaleChannel.telefono,
      customerName: 'Granja Santa Fe',
    ));

    expect(result.isOk, isTrue);
    expect(repository.saved!.status, OrderStatus.pendiente);
    expect(repository.saved!.deliveryPersonId, isNull);
  });
}
