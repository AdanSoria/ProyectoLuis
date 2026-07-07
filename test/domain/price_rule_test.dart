import 'package:agropos/domain/entities/cart_line.dart';
import 'package:agropos/domain/entities/catalog_item.dart';
import 'package:agropos/domain/entities/product_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 6, 12);

  const granel = ProductVariant(
    id: 'v-granel',
    productId: 'p1',
    name: 'Granel kg',
    costPriceCents: 1300,
    salePriceCents: 1800,
    stock: 50,
    unit: 'kg',
    contentUnits: 1,
    priceTiers: [PriceTier(minQuantity: 10, unitPriceCents: 1700)],
  );

  Product product() => Product(
        id: 'p1',
        name: 'Alimento',
        category: 'Alimentos',
        costPriceCents: 1300,
        salePriceCents: 1800,
        unit: 'kg',
        stock: 50,
        createdAt: t0,
        updatedAt: t0,
        variants: [granel.copyWith(isDefault: true)],
      );

  final service = Service(
    id: 's1',
    name: 'Flete',
    category: 'Servicios',
    costPriceCents: 0,
    salePriceCents: 15000,
    createdAt: t0,
    updatedAt: t0,
  );

  test('lista: cantidad por debajo del escalón, sin regateo', () {
    final line = CartLine(item: product(), quantity: 5);
    expect(line.priceRule, PriceRule.lista);
    expect(line.unitPriceCents, 1800);
  });

  test('mayoreo: la cantidad alcanza el PriceTier', () {
    final line = CartLine(item: product(), quantity: 10);
    expect(line.priceRule, PriceRule.mayoreo);
    expect(line.unitPriceCents, 1700);
  });

  test('manual: regateo por línea gana sobre lista y escalón', () {
    final line = CartLine(item: product(), quantity: 10, priceOverrideCents: 1500);
    expect(line.priceRule, PriceRule.manual);
    expect(line.unitPriceCents, 1500);
    // El precio de lista (con escalón) se conserva para auditoría.
    expect(line.listUnitPriceCents, 1700);
  });

  test('servicio (o ítem libre) siempre es lista', () {
    final line = CartLine(item: service, quantity: 3);
    expect(line.priceRule, PriceRule.lista);
  });
}
