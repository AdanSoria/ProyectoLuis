/// Elemento vendible del catálogo.
///
/// Regla de negocio central:
/// - [Product] descuenta inventario físico al venderse.
/// - [Service] (flete, consulta veterinaria, aplicación a domicilio) se
///   cobra sin afectar stock, pero SÍ participa en el cálculo de utilidad
///   mediante su `precio_costo` (ej. gasolina del flete).
sealed class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    required this.category,
    required this.costPriceCents,
    required this.salePriceCents,
    this.unit = 'pieza',
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// UUID v4 generado en el cliente.
  final String id;
  final String name;
  final String category;

  /// `precio_costo` en centavos.
  final int costPriceCents;

  /// `precio_venta` en centavos.
  final int salePriceCents;

  /// Unidad de venta: pieza, bulto, kg, litro, servicio...
  final String unit;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isService;

  /// Margen unitario en centavos.
  int get unitMarginCents => salePriceCents - costPriceCents;
}

class Product extends CatalogItem {
  const Product({
    required super.id,
    required super.name,
    required super.category,
    required super.costPriceCents,
    required super.salePriceCents,
    super.unit,
    super.active,
    required super.createdAt,
    required super.updatedAt,
    required this.stock,
  });

  /// Existencias físicas. Se permite fracción (kg, litros a granel).
  final double stock;

  @override
  bool get isService => false;

  bool hasStockFor(double quantity) => stock >= quantity;

  Product copyWith({
    String? name,
    String? category,
    int? costPriceCents,
    int? salePriceCents,
    String? unit,
    bool? active,
    double? stock,
    DateTime? updatedAt,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        costPriceCents: costPriceCents ?? this.costPriceCents,
        salePriceCents: salePriceCents ?? this.salePriceCents,
        unit: unit ?? this.unit,
        active: active ?? this.active,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        stock: stock ?? this.stock,
      );
}

class Service extends CatalogItem {
  const Service({
    required super.id,
    required super.name,
    required super.category,
    required super.costPriceCents,
    required super.salePriceCents,
    super.unit = 'servicio',
    super.active,
    required super.createdAt,
    required super.updatedAt,
  });

  @override
  bool get isService => true;

  Service copyWith({
    String? name,
    String? category,
    int? costPriceCents,
    int? salePriceCents,
    String? unit,
    bool? active,
    DateTime? updatedAt,
  }) =>
      Service(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        costPriceCents: costPriceCents ?? this.costPriceCents,
        salePriceCents: salePriceCents ?? this.salePriceCents,
        unit: unit ?? this.unit,
        active: active ?? this.active,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
