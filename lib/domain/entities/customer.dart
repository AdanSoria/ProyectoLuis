/// Categoría comercial del cliente: define su trato de precios.
enum CustomerCategory {
  minorista('minorista', 'Minorista'),
  mayorista('mayorista', 'Mayorista');

  const CustomerCategory(this.code, this.label);
  final String code;
  final String label;

  static CustomerCategory fromCode(String code) =>
      values.firstWhere((v) => v.code == code,
          orElse: () => CustomerCategory.minorista);
}

/// Cliente del mini-CRM. Captura mínima (con nombre o teléfono basta para
/// registrar un pedido), pero con perfil comercial completo:
/// - [category] y [discountPercent]: su descuento base se aplica solo
///   al asignarlo a una venta (anulable manualmente en el ticket).
/// - [totalSpentCents] / [purchaseCount]: historial acumulado de compras
///   COBRADAS, actualizado atómicamente junto con cada transacción.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.notes,
    this.category = CustomerCategory.minorista,
    this.discountPercent = 0,
    this.totalSpentCents = 0,
    this.purchaseCount = 0,
    this.lastPurchaseAt,
    required this.createdAt,
  });

  /// UUID v4 generado en el cliente.
  final String id;
  final String name;
  final String? phone;
  final String? notes;

  final CustomerCategory category;

  /// Descuento base del perfil (0–100). Se sugiere automáticamente al
  /// asignar el cliente al carrito.
  final double discountPercent;

  /// `total_spent`: dinero realmente cobrado a este cliente, en centavos.
  final int totalSpentCents;
  final int purchaseCount;
  final DateTime? lastPurchaseAt;

  final DateTime createdAt;

  int get averageTicketCents =>
      purchaseCount == 0 ? 0 : totalSpentCents ~/ purchaseCount;

  /// Descuento en centavos que el perfil sugiere para un subtotal dado.
  int discountFor(int subtotalCents) =>
      (subtotalCents * discountPercent / 100).round();

  Customer copyWith({
    String? name,
    String? phone,
    String? notes,
    CustomerCategory? category,
    double? discountPercent,
    int? totalSpentCents,
    int? purchaseCount,
    DateTime? lastPurchaseAt,
  }) =>
      Customer(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        notes: notes ?? this.notes,
        category: category ?? this.category,
        discountPercent: discountPercent ?? this.discountPercent,
        totalSpentCents: totalSpentCents ?? this.totalSpentCents,
        purchaseCount: purchaseCount ?? this.purchaseCount,
        lastPurchaseAt: lastPurchaseAt ?? this.lastPurchaseAt,
        createdAt: createdAt,
      );
}
