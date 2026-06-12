/// Regla de precio por volumen: a partir de [minQuantity] unidades,
/// el precio unitario baja a [unitPriceCents] (mayoreo dentro de la
/// misma variante, ej. "10+ kg de granel a $17.00/kg").
class PriceTier {
  const PriceTier({required this.minQuantity, required this.unitPriceCents});

  final double minQuantity;
  final int unitPriceCents;
}

/// Variante vendible de un producto (SKU): "Costal 50 kg", "Granel 1 kg".
/// Cada variante tiene su propio precio, costo y **stock independiente**.
///
/// Convención importante: todo producto tiene al menos una variante
/// "default" cuyo `id` es el MISMO uuid del producto padre — así los
/// productos simples no pagan complejidad extra y los datos creados
/// antes de las variantes siguen siendo válidos.
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    this.sku,
    required this.costPriceCents,
    required this.salePriceCents,
    required this.stock,
    this.unit = 'pieza',
    this.contentUnits = 1,
    this.isDefault = false,
    this.active = true,
    this.priceTiers = const [],
  });

  /// UUID v4 (== uuid del producto para la variante default).
  final String id;
  final String productId;

  /// Nombre corto de la presentación: "Costal 50 kg", "Granel kg".
  final String name;

  /// Código propio (opcional) para etiquetas/escáner futuros.
  final String? sku;

  final int costPriceCents;
  final int salePriceCents;
  final double stock;
  final String unit;

  /// Cuántas unidades base contiene esta presentación. Es la llave del
  /// **desensamble**: un costal de 50 kg tiene `contentUnits = 50` y el
  /// granel de 1 kg tiene `contentUnits = 1`, así que romper 1 costal
  /// produce 50 de granel.
  final double contentUnits;

  final bool isDefault;
  final bool active;

  /// Precios escalonados por volumen (ordenados o no; se busca el mejor).
  final List<PriceTier> priceTiers;

  /// Precio unitario efectivo para [quantity]: el escalón de mayor
  /// `minQuantity` que la cantidad alcance, o el precio normal.
  int priceForQuantity(double quantity) {
    PriceTier? best;
    for (final tier in priceTiers) {
      if (quantity >= tier.minQuantity &&
          (best == null || tier.minQuantity > best.minQuantity)) {
        best = tier;
      }
    }
    return best?.unitPriceCents ?? salePriceCents;
  }

  bool hasStockFor(double quantity) => stock >= quantity;

  /// Margen unitario al precio de lista.
  int get unitMarginCents => salePriceCents - costPriceCents;

  ProductVariant copyWith({
    String? name,
    String? sku,
    int? costPriceCents,
    int? salePriceCents,
    double? stock,
    String? unit,
    double? contentUnits,
    bool? isDefault,
    bool? active,
    List<PriceTier>? priceTiers,
  }) =>
      ProductVariant(
        id: id,
        productId: productId,
        name: name ?? this.name,
        sku: sku ?? this.sku,
        costPriceCents: costPriceCents ?? this.costPriceCents,
        salePriceCents: salePriceCents ?? this.salePriceCents,
        stock: stock ?? this.stock,
        unit: unit ?? this.unit,
        contentUnits: contentUnits ?? this.contentUnits,
        isDefault: isDefault ?? this.isDefault,
        active: active ?? this.active,
        priceTiers: priceTiers ?? this.priceTiers,
      );
}
