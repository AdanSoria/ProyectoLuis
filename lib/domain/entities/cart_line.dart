import 'catalog_item.dart';
import 'product_variant.dart';

/// Regla que determinó el precio unitario efectivo de una línea. Se usa
/// para dar transparencia en el ticket (etiqueta por línea).
enum PriceRule {
  /// Precio de lista de la variante/servicio.
  lista,

  /// Se aplicó un escalón de volumen (`PriceTier`).
  mayoreo,

  /// Sobreescritura manual del cajero (regateo).
  manual,
}

/// Línea del carrito en construcción (aún no es una venta).
/// Es la entrada del caso de uso `ProcessTransactionUseCase`.
///
/// El precio efectivo de la línea se resuelve en este orden:
/// 1. [priceOverrideCents] — "regateo" capturado en el mostrador;
/// 2. precio escalonado por volumen de la variante (si la cantidad
///    alcanza un escalón);
/// 3. precio de lista de la variante (o del servicio).
class CartLine {
  const CartLine({
    required this.item,
    required this.quantity,
    this.variant,
    this.priceOverrideCents,
  });

  final CatalogItem item;
  final double quantity;

  /// Variante elegida (solo productos). `null` = variante default.
  final ProductVariant? variant;

  /// Precio unitario negociado manualmente (regateo). `null` = lista.
  final int? priceOverrideCents;

  /// Variante efectiva sobre la que se mueve stock.
  ProductVariant? get effectiveVariant => switch (item) {
        final Product p => variant ?? p.defaultVariant,
        Service() => null,
      };

  /// Precio unitario de lista (con escalón por volumen aplicado).
  int get listUnitPriceCents =>
      effectiveVariant?.priceForQuantity(quantity) ?? item.salePriceCents;

  /// Precio unitario efectivo (regateo > escalón > lista).
  int get unitPriceCents => priceOverrideCents ?? listUnitPriceCents;

  int get unitCostCents =>
      effectiveVariant?.costPriceCents ?? item.costPriceCents;

  bool get hasOverride => priceOverrideCents != null;

  /// Regla que fijó [unitPriceCents] (solo lectura, deriva de los getters
  /// existentes): regateo > escalón de volumen > lista.
  PriceRule get priceRule {
    if (hasOverride) return PriceRule.manual;
    final base = effectiveVariant?.salePriceCents ?? item.salePriceCents;
    if (listUnitPriceCents != base) return PriceRule.mayoreo;
    return PriceRule.lista;
  }

  /// Nombre para el ticket: incluye la variante cuando no es la default.
  String get displayName {
    final v = effectiveVariant;
    if (v == null || v.isDefault) return item.name;
    return '${item.name} · ${v.name}';
  }

  int get totalCents => (unitPriceCents * quantity).round();

  int get totalCostCents => (unitCostCents * quantity).round();

  CartLine copyWith({double? quantity, int? Function()? priceOverride}) =>
      CartLine(
        item: item,
        quantity: quantity ?? this.quantity,
        variant: variant,
        priceOverrideCents:
            priceOverride != null ? priceOverride() : priceOverrideCents,
      );
}
