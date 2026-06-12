import '../../domain/entities/customer.dart';

class CustomerModel {
  CustomerModel._();

  static Map<String, Object?> toRow(Customer c) => {
        'id': c.id,
        'nombre': c.name,
        'telefono': c.phone,
        'notas': c.notes,
        'categoria': c.category.code,
        'descuento_pct': c.discountPercent,
        'total_gastado': c.totalSpentCents,
        'compras': c.purchaseCount,
        'ultima_compra': c.lastPurchaseAt?.toIso8601String(),
        'creado_en': c.createdAt.toIso8601String(),
      };

  static Customer fromRow(Map<String, Object?> row) => Customer(
        id: row['id'] as String,
        name: row['nombre'] as String,
        phone: row['telefono'] as String?,
        notes: row['notas'] as String?,
        category:
            CustomerCategory.fromCode((row['categoria'] as String?) ?? ''),
        discountPercent: (row['descuento_pct'] as num?)?.toDouble() ?? 0,
        totalSpentCents: (row['total_gastado'] as num?)?.toInt() ?? 0,
        purchaseCount: (row['compras'] as num?)?.toInt() ?? 0,
        lastPurchaseAt: row['ultima_compra'] == null
            ? null
            : DateTime.parse(row['ultima_compra'] as String),
        createdAt: DateTime.parse(row['creado_en'] as String),
      );

  static Map<String, dynamic> toSyncJson(Customer c) => toRow(c);
}
