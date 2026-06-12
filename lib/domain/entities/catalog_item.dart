import 'product_variant.dart';

/// Elemento vendible del catálogo.
///
/// Regla de negocio central:
/// - [Product] descuenta inventario físico al venderse (por variante).
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
    this.variants = const [],
  });

  /// Existencias de la variante default. Se permite fracción (kg, litros).
  final double stock;

  /// Presentaciones del producto (la default va primero). Vacía solo en
  /// objetos construidos en memoria: [defaultVariant] cubre ese caso
  /// proyectando los campos del propio producto.
  final List<ProductVariant> variants;

  @override
  bool get isService => false;

  /// Variante principal. Por convención su id == id del producto.
  ProductVariant get defaultVariant => variants.isNotEmpty
      ? variants.first
      : ProductVariant(
          id: id,
          productId: id,
          name: 'Estándar',
          costPriceCents: costPriceCents,
          salePriceCents: salePriceCents,
          stock: stock,
          unit: unit,
          contentUnits: 1,
          isDefault: true,
        );

  /// Variantes activas en orden de venta (default primero).
  List<ProductVariant> get sellableVariants => variants.isEmpty
      ? [defaultVariant]
      : [for (final v in variants) if (v.active) v];

  bool get hasMultipleVariants => sellableVariants.length > 1;

  /// Precio "desde" para la tarjeta del catálogo.
  int get minSalePriceCents => sellableVariants
      .map((v) => v.salePriceCents)
      .reduce((a, b) => a < b ? a : b);

  bool hasStockFor(double quantity) => stock >= quantity;

  /// Crea un producto simple con su variante default (id compartido).
  factory Product.simple({
    required String id,
    required String name,
    required String category,
    required int costPriceCents,
    required int salePriceCents,
    String unit = 'pieza',
    bool active = true,
    required DateTime createdAt,
    required DateTime updatedAt,
    required double stock,
  }) =>
      Product(
        id: id,
        name: name,
        category: category,
        costPriceCents: costPriceCents,
        salePriceCents: salePriceCents,
        unit: unit,
        active: active,
        createdAt: createdAt,
        updatedAt: updatedAt,
        stock: stock,
        variants: [
          ProductVariant(
            id: id,
            productId: id,
            name: 'Estándar',
            costPriceCents: costPriceCents,
            salePriceCents: salePriceCents,
            stock: stock,
            unit: unit,
            contentUnits: 1,
            isDefault: true,
          ),
        ],
      );

  Product copyWith({
    String? name,
    String? category,
    int? costPriceCents,
    int? salePriceCents,
    String? unit,
    bool? active,
    double? stock,
    DateTime? updatedAt,
    List<ProductVariant>? variants,
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
        variants: variants ?? this.variants,
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
