import '../../domain/entities/transaction.dart';

class TransactionModel {
  TransactionModel._();

  static Map<String, Object?> toRow(Transaction t) => {
        'id': t.id,
        'folio': t.folio,
        'tipo': t.kind.code,
        'canal': t.channel.code,
        'estado': t.status.code,
        'cliente_id': t.customerId,
        'cliente_nombre': t.customerName,
        'cliente_telefono': t.customerPhone,
        'repartidor_id': t.deliveryPersonId,
        'repartidor_nombre': t.deliveryPersonName,
        'metodo_pago': t.paymentMethod.code,
        'monto_recibido': t.amountPaidCents,
        // Métricas financieras denormalizadas para reportes SQL directos.
        'subtotal': t.subtotalCents,
        'deducciones': t.deductionsCents,
        'total': t.totalCents,
        'precio_costo_total': t.costTotalCents,
        'utilidad_neta': t.netProfitCents,
        'notas': t.notes,
        'creado_en': t.createdAt.toIso8601String(),
        'actualizado_en': t.updatedAt.toIso8601String(),
      };

  static Map<String, Object?> lineToRow(String transactionId, TransactionLine l) => {
        'id': l.id,
        'transaccion_id': transactionId,
        'item_id': l.itemId,
        'item_nombre': l.itemName,
        'item_tipo': l.isService ? 'servicio' : 'producto',
        'cantidad': l.quantity,
        'precio_venta': l.unitPriceCents,
        'precio_costo': l.unitCostCents,
        'importe': l.totalCents,
        'costo': l.totalCostCents,
        'variante_id': l.variantId,
        'variante_nombre': l.variantName,
        'precio_lista': l.listUnitPriceCents,
      };

  static TransactionLine lineFromRow(Map<String, Object?> row) =>
      TransactionLine(
        id: row['id'] as String,
        itemId: row['item_id'] as String,
        itemName: row['item_nombre'] as String,
        isService: row['item_tipo'] == 'servicio',
        quantity: (row['cantidad'] as num).toDouble(),
        unitPriceCents: (row['precio_venta'] as num).toInt(),
        unitCostCents: (row['precio_costo'] as num).toInt(),
        variantId: row['variante_id'] as String?,
        variantName: row['variante_nombre'] as String?,
        listUnitPriceCents: (row['precio_lista'] as num?)?.toInt(),
      );

  static Transaction fromRows(
    Map<String, Object?> row,
    List<Map<String, Object?>> lineRows,
  ) =>
      Transaction(
        id: row['id'] as String,
        folio: row['folio'] as String,
        kind: TransactionKind.fromCode(row['tipo'] as String),
        channel: SaleChannel.fromCode(row['canal'] as String),
        status: OrderStatus.fromCode(row['estado'] as String),
        lines: [for (final l in lineRows) lineFromRow(l)],
        deductionsCents: (row['deducciones'] as num? ?? 0).toInt(),
        paymentMethod: PaymentMethod.fromCode(row['metodo_pago'] as String),
        amountPaidCents: (row['monto_recibido'] as num? ?? 0).toInt(),
        customerId: row['cliente_id'] as String?,
        customerName: row['cliente_nombre'] as String?,
        customerPhone: row['cliente_telefono'] as String?,
        deliveryPersonId: row['repartidor_id'] as String?,
        deliveryPersonName: row['repartidor_nombre'] as String?,
        notes: row['notas'] as String?,
        createdAt: DateTime.parse(row['creado_en'] as String),
        updatedAt: DateTime.parse(row['actualizado_en'] as String),
      );

  /// Payload completo (cabecera + líneas) para el backend.
  static Map<String, dynamic> toSyncJson(Transaction t) => {
        ...toRow(t),
        'lineas': [for (final l in t.lines) lineToRow(t.id, l)],
      };
}
