import 'package:agropos/data/export/excel_exporter.dart';
import 'package:agropos/domain/entities/catalog_item.dart';
import 'package:agropos/domain/entities/transaction.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 6, 10, 9, 30);

  Transaction txn({required OrderStatus status, String folio = '260610-AAAA'}) =>
      Transaction(
        id: 'txn-$folio',
        folio: folio,
        kind: TransactionKind.ventaMostrador,
        channel: SaleChannel.mostrador,
        status: status,
        amountPaidCents: 113000,
        lines: const [
          TransactionLine(
            id: 'l1',
            itemId: 'p1',
            itemName: 'Fertilizante',
            isService: false,
            quantity: 1,
            unitPriceCents: 95000,
            unitCostCents: 78000,
          ),
          TransactionLine(
            id: 'l2',
            itemId: 's1',
            itemName: 'Flete local',
            isService: true,
            quantity: 1,
            unitPriceCents: 15000,
            unitCostCents: 6000,
          ),
        ],
        createdAt: t0,
        updatedAt: t0,
      );

  final catalog = <CatalogItem>[
    Product(
      id: 'p1',
      name: 'Fertilizante',
      category: 'Fertilizantes',
      costPriceCents: 78000,
      salePriceCents: 95000,
      unit: 'bulto',
      stock: 40,
      createdAt: t0,
      updatedAt: t0,
    ),
    Service(
      id: 's1',
      name: 'Flete local',
      category: 'Servicios',
      costPriceCents: 6000,
      salePriceCents: 15000,
      createdAt: t0,
      updatedAt: t0,
    ),
  ];

  test('genera las 3 hojas con datos y totales correctos', () {
    final bytes = const ExcelExporter().buildReport(
      transactions: [
        txn(status: OrderStatus.completado),
        txn(status: OrderStatus.cancelado, folio: '260610-BBBB'),
      ],
      catalog: catalog,
    );

    final excel = Excel.decodeBytes(bytes);
    expect(excel.tables.keys.toSet(),
        containsAll({'Ventas', 'Detalle', 'Inventario'}));

    String text(Data? cell) => cell?.value?.toString() ?? '';
    double number(Data? cell) =>
        double.parse(cell!.value!.toString());

    // Ventas: encabezado + 2 transacciones + separador + totales.
    final ventas = excel.tables['Ventas']!.rows;
    expect(text(ventas[0][0]), 'Folio');
    expect(text(ventas[1][0]), '260610-AAAA');
    expect(number(ventas[1][11]), 1100.0); // total $1,100.00
    expect(number(ventas[1][13]), 260.0); // utilidad neta $260.00

    // Totales solo cuentan la completada (la cancelada queda fuera).
    final totals = ventas.last;
    expect(text(totals[0]), contains('TOTALES'));
    expect(number(totals[11]), 1100.0);
    expect(number(totals[13]), 260.0);

    // Detalle: encabezado + 2 líneas por transacción.
    final detalle = excel.tables['Detalle']!.rows;
    expect(detalle, hasLength(1 + 4));
    expect(text(detalle[2][3]), 'Flete local');
    expect(text(detalle[2][5]), 'Servicio');

    // Inventario: encabezado + 1 variante de producto + 1 servicio.
    final inventario = excel.tables['Inventario']!.rows;
    expect(inventario, hasLength(3));
    expect(text(inventario[1][0]), 'Fertilizante');
    expect(number(inventario[1][10]), 40.0); // stock
    expect(number(inventario[1][11]), 40 * 780.0); // valor a costo
    expect(text(inventario[2][10]), ''); // servicio: sin stock
  });
}
