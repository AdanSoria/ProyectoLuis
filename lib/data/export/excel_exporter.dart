import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../domain/entities/catalog_item.dart';
import '../../domain/entities/transaction.dart';

/// Genera el reporte `.xlsx` con tres hojas:
/// - **Ventas**: una fila por transacción con todas sus métricas
///   financieras y una fila de totales (solo completadas).
/// - **Detalle**: una fila por línea vendida (ideal para tablas dinámicas).
/// - **Inventario**: catálogo valorizado a costo.
///
/// Los montos van como números (pesos con decimales) para que Excel
/// pueda sumar/filtrar directamente.
class ExcelExporter {
  const ExcelExporter();

  Uint8List buildReport({
    required List<Transaction> transactions,
    required List<CatalogItem> catalog,
  }) {
    final excel = Excel.createExcel();

    _buildSalesSheet(excel['Ventas'], transactions);
    _buildLinesSheet(excel['Detalle'], transactions);
    _buildInventorySheet(excel['Inventario'], catalog);

    excel.delete('Sheet1'); // hoja vacía por defecto

    return Uint8List.fromList(excel.encode()!);
  }

  // ---------------------------------------------------------------- hojas

  void _buildSalesSheet(Sheet sheet, List<Transaction> transactions) {
    sheet.appendRow([
      TextCellValue('Folio'),
      TextCellValue('Fecha'),
      TextCellValue('Tipo'),
      TextCellValue('Canal'),
      TextCellValue('Estado'),
      TextCellValue('Cliente'),
      TextCellValue('Teléfono'),
      TextCellValue('Repartidor'),
      TextCellValue('Método de pago'),
      TextCellValue('Subtotal'),
      TextCellValue('Descuento'),
      TextCellValue('Total'),
      TextCellValue('Costo'),
      TextCellValue('Utilidad neta'),
      TextCellValue('Artículos'),
      TextCellValue('Notas'),
    ]);

    for (final t in transactions) {
      sheet.appendRow([
        TextCellValue(t.folio),
        TextCellValue(_date(t.createdAt)),
        TextCellValue(t.kind.label),
        TextCellValue(t.channel.label),
        TextCellValue(t.status.label),
        TextCellValue(t.customerName ?? 'Mostrador'),
        TextCellValue(t.customerPhone ?? ''),
        TextCellValue(t.deliveryPersonName ?? ''),
        TextCellValue(t.paymentMethod.label),
        DoubleCellValue(t.subtotalCents / 100),
        DoubleCellValue(t.deductionsCents / 100),
        DoubleCellValue(t.totalCents / 100),
        DoubleCellValue(t.costTotalCents / 100),
        DoubleCellValue(t.netProfitCents / 100),
        TextCellValue(_lineSummary(t)),
        TextCellValue(t.notes ?? ''),
      ]);
    }

    // Totales del dinero que realmente entró.
    final completed =
        transactions.where((t) => t.status == OrderStatus.completado);
    int subtotal = 0, deductions = 0, total = 0, cost = 0, profit = 0;
    for (final t in completed) {
      subtotal += t.subtotalCents;
      deductions += t.deductionsCents;
      total += t.totalCents;
      cost += t.costTotalCents;
      profit += t.netProfitCents;
    }
    sheet.appendRow(List<CellValue?>.filled(16, null));
    sheet.appendRow([
      TextCellValue('TOTALES (solo completadas)'),
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      DoubleCellValue(subtotal / 100),
      DoubleCellValue(deductions / 100),
      DoubleCellValue(total / 100),
      DoubleCellValue(cost / 100),
      DoubleCellValue(profit / 100),
      null,
      null,
    ]);
  }

  void _buildLinesSheet(Sheet sheet, List<Transaction> transactions) {
    sheet.appendRow([
      TextCellValue('Folio'),
      TextCellValue('Fecha'),
      TextCellValue('Estado'),
      TextCellValue('Artículo'),
      TextCellValue('Presentación'),
      TextCellValue('Tipo'),
      TextCellValue('Cantidad'),
      TextCellValue('Precio lista'),
      TextCellValue('Precio unitario'),
      TextCellValue('Costo unitario'),
      TextCellValue('Importe'),
      TextCellValue('Costo'),
      TextCellValue('Utilidad'),
    ]);

    for (final t in transactions) {
      for (final line in t.lines) {
        sheet.appendRow([
          TextCellValue(t.folio),
          TextCellValue(_date(t.createdAt)),
          TextCellValue(t.status.label),
          TextCellValue(line.itemName),
          TextCellValue(line.variantName ?? ''),
          TextCellValue(line.isService ? 'Servicio' : 'Producto'),
          DoubleCellValue(line.quantity),
          DoubleCellValue(line.listUnitPriceCents / 100),
          DoubleCellValue(line.unitPriceCents / 100),
          DoubleCellValue(line.unitCostCents / 100),
          DoubleCellValue(line.totalCents / 100),
          DoubleCellValue(line.totalCostCents / 100),
          DoubleCellValue((line.totalCents - line.totalCostCents) / 100),
        ]);
      }
    }
  }

  /// Una fila por VARIANTE (los servicios ocupan una sola fila).
  void _buildInventorySheet(Sheet sheet, List<CatalogItem> catalog) {
    sheet.appendRow([
      TextCellValue('Nombre'),
      TextCellValue('Presentación'),
      TextCellValue('SKU'),
      TextCellValue('Categoría'),
      TextCellValue('Tipo'),
      TextCellValue('Unidad'),
      TextCellValue('Contiene'),
      TextCellValue('Precio costo'),
      TextCellValue('Precio venta'),
      TextCellValue('Margen %'),
      TextCellValue('Stock'),
      TextCellValue('Valor a costo'),
      TextCellValue('Activo'),
    ]);

    double margin(int cost, int sale) =>
        sale == 0 ? 0 : double.parse(((sale - cost) * 100 / sale).toStringAsFixed(1));

    for (final item in catalog) {
      if (item is! Product) {
        sheet.appendRow([
          TextCellValue(item.name),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(item.category),
          TextCellValue('Servicio'),
          TextCellValue(item.unit),
          TextCellValue(''),
          DoubleCellValue(item.costPriceCents / 100),
          DoubleCellValue(item.salePriceCents / 100),
          DoubleCellValue(margin(item.costPriceCents, item.salePriceCents)),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(item.active ? 'Sí' : 'No'),
        ]);
        continue;
      }

      final variants =
          item.variants.isEmpty ? [item.defaultVariant] : item.variants;
      for (final variant in variants) {
        sheet.appendRow([
          TextCellValue(item.name),
          TextCellValue(variant.name),
          TextCellValue(variant.sku ?? ''),
          TextCellValue(item.category),
          TextCellValue('Producto'),
          TextCellValue(variant.unit),
          DoubleCellValue(variant.contentUnits),
          DoubleCellValue(variant.costPriceCents / 100),
          DoubleCellValue(variant.salePriceCents / 100),
          DoubleCellValue(
              margin(variant.costPriceCents, variant.salePriceCents)),
          DoubleCellValue(variant.stock),
          DoubleCellValue(variant.stock * variant.costPriceCents / 100),
          TextCellValue(item.active && variant.active ? 'Sí' : 'No'),
        ]);
      }
    }
  }

  // ------------------------------------------------------------- helpers

  String _date(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  String _lineSummary(Transaction t) => [
        for (final line in t.lines)
          '${line.quantity % 1 == 0 ? line.quantity.toInt() : line.quantity}× ${line.itemName}',
      ].join(', ');
}
