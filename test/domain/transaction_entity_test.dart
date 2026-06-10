import 'package:agropos/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 6, 10, 12);

  TransactionLine line({
    String id = 'l1',
    bool isService = false,
    double quantity = 1,
    required int price,
    required int cost,
  }) =>
      TransactionLine(
        id: id,
        itemId: 'item-$id',
        itemName: 'Artículo $id',
        isService: isService,
        quantity: quantity,
        unitPriceCents: price,
        unitCostCents: cost,
      );

  group('Métricas financieras de Transaction', () {
    test('calcula subtotal, total, costo, utilidad neta y cambio', () {
      final txn = Transaction(
        id: 't1',
        folio: '260610-AAAA',
        kind: TransactionKind.ventaMostrador,
        channel: SaleChannel.mostrador,
        status: OrderStatus.completado,
        lines: [
          // 2 bultos de fertilizante: venta 950.00, costo 780.00
          line(id: 'l1', quantity: 2, price: 95000, cost: 78000),
          // 1 flete: venta 150.00, costo 60.00 (servicio con costo)
          line(id: 'l2', isService: true, price: 15000, cost: 6000),
        ],
        deductionsCents: 5000, // descuento de $50
        amountPaidCents: 250000, // pagó con $2,500
        createdAt: t0,
        updatedAt: t0,
      );

      expect(txn.subtotalCents, 2 * 95000 + 15000); // 205000
      expect(txn.totalCents, 200000);
      expect(txn.costTotalCents, 2 * 78000 + 6000); // 162000
      expect(txn.netProfitCents, 200000 - 162000); // 38000
      expect(txn.changeCents, 50000);
      expect(txn.itemCount, 3);
    });

    test('cantidades fraccionarias redondean a centavos', () {
      final txn = Transaction(
        id: 't2',
        folio: '260610-BBBB',
        kind: TransactionKind.ventaMostrador,
        channel: SaleChannel.mostrador,
        status: OrderStatus.completado,
        lines: [
          // 2.5 kg a $42.00/kg = $105.00
          line(id: 'l1', quantity: 2.5, price: 4200, cost: 3100),
        ],
        createdAt: t0,
        updatedAt: t0,
      );

      expect(txn.subtotalCents, 10500);
      expect(txn.costTotalCents, 7750);
      expect(txn.netProfitCents, 2750);
    });

    test('el total nunca es negativo aunque el descuento sea mayor', () {
      final txn = Transaction(
        id: 't3',
        folio: '260610-CCCC',
        kind: TransactionKind.ventaMostrador,
        channel: SaleChannel.mostrador,
        status: OrderStatus.completado,
        lines: [line(price: 1000, cost: 500)],
        deductionsCents: 99999,
        createdAt: t0,
        updatedAt: t0,
      );

      expect(txn.totalCents, 0);
    });
  });

  group('Máquina de estados de pedidos', () {
    test('transiciones válidas', () {
      expect(
          OrderStatus.pendiente.canTransitionTo(OrderStatus.asignado), isTrue);
      expect(
          OrderStatus.pendiente.canTransitionTo(OrderStatus.cancelado), isTrue);
      expect(
          OrderStatus.asignado.canTransitionTo(OrderStatus.completado), isTrue);
      expect(
          OrderStatus.asignado.canTransitionTo(OrderStatus.cancelado), isTrue);
      // Reasignación de repartidor permitida.
      expect(
          OrderStatus.asignado.canTransitionTo(OrderStatus.asignado), isTrue);
    });

    test('transiciones inválidas', () {
      // No se puede completar sin pasar por asignado.
      expect(OrderStatus.pendiente.canTransitionTo(OrderStatus.completado),
          isFalse);
      // Los estados finales son inmutables.
      expect(OrderStatus.completado.canTransitionTo(OrderStatus.asignado),
          isFalse);
      expect(OrderStatus.completado.canTransitionTo(OrderStatus.cancelado),
          isFalse);
      expect(OrderStatus.cancelado.canTransitionTo(OrderStatus.pendiente),
          isFalse);
    });

    test('estados finales', () {
      expect(OrderStatus.completado.isFinal, isTrue);
      expect(OrderStatus.cancelado.isFinal, isTrue);
      expect(OrderStatus.pendiente.isFinal, isFalse);
      expect(OrderStatus.asignado.isFinal, isFalse);
    });
  });
}
