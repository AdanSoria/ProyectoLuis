import 'catalog_item.dart';

/// Línea del carrito en construcción (aún no es una venta).
/// Es la entrada del caso de uso [ProcessTransactionUseCase].
class CartLine {
  const CartLine({required this.item, required this.quantity});

  final CatalogItem item;
  final double quantity;

  int get totalCents => (item.salePriceCents * quantity).round();

  CartLine copyWith({double? quantity}) =>
      CartLine(item: item, quantity: quantity ?? this.quantity);
}
