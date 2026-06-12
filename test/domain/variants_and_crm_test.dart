import 'package:agropos/core/errors/failures.dart';
import 'package:agropos/core/utils/result.dart';
import 'package:agropos/domain/entities/cart_line.dart';
import 'package:agropos/domain/entities/catalog_item.dart';
import 'package:agropos/domain/entities/customer.dart';
import 'package:agropos/domain/entities/product_variant.dart';
import 'package:agropos/domain/repositories/catalog_repository.dart';
import 'package:agropos/domain/usecases/break_variant_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 6, 12);

  ProductVariant variant({
    String id = 'v-granel',
    String productId = 'p1',
    String name = 'Granel kg',
    int cost = 1300,
    int sale = 1800,
    double stock = 20,
    double content = 1,
    bool isDefault = false,
    List<PriceTier> tiers = const [],
  }) =>
      ProductVariant(
        id: id,
        productId: productId,
        name: name,
        costPriceCents: cost,
        salePriceCents: sale,
        stock: stock,
        unit: 'kg',
        contentUnits: content,
        isDefault: isDefault,
        priceTiers: tiers,
      );

  Product product({List<ProductVariant>? variants}) => Product(
        id: 'p1',
        name: 'Alimento para becerro',
        category: 'Alimentos',
        costPriceCents: 52000,
        salePriceCents: 64000,
        unit: 'bulto',
        createdAt: t0,
        updatedAt: t0,
        stock: 35,
        variants: variants ??
            [
              variant(
                  id: 'p1',
                  name: 'Costal 40 kg',
                  cost: 52000,
                  sale: 64000,
                  stock: 35,
                  content: 40,
                  isDefault: true),
              variant(tiers: const [
                PriceTier(minQuantity: 10, unitPriceCents: 1700),
                PriceTier(minQuantity: 25, unitPriceCents: 1600),
              ]),
            ],
      );

  group('Precios escalonados por volumen', () {
    test('elige el mejor escalón alcanzado o el precio de lista', () {
      final granel = product().variants[1];

      expect(granel.priceForQuantity(1), 1800); // menudeo
      expect(granel.priceForQuantity(9.5), 1800);
      expect(granel.priceForQuantity(10), 1700); // primer escalón
      expect(granel.priceForQuantity(24), 1700);
      expect(granel.priceForQuantity(25), 1600); // mayor escalón
      expect(granel.priceForQuantity(100), 1600);
    });
  });

  group('CartLine: variante, escalón y regateo', () {
    test('usa la variante elegida y su escalón por cantidad', () {
      final p = product();
      final line = CartLine(item: p, variant: p.variants[1], quantity: 10);

      expect(line.displayName, 'Alimento para becerro · Granel kg');
      expect(line.listUnitPriceCents, 1700);
      expect(line.unitPriceCents, 1700);
      expect(line.totalCents, 17000);
      expect(line.unitCostCents, 1300);
    });

    test('sin variante usa la default del producto', () {
      final line = CartLine(item: product(), quantity: 2);

      expect(line.effectiveVariant!.id, 'p1'); // default comparte uuid
      expect(line.unitPriceCents, 64000);
      expect(line.displayName, 'Alimento para becerro'); // sin sufijo
    });

    test('el regateo manda sobre lista y escalón, y queda auditable', () {
      final p = product();
      final line = CartLine(
        item: p,
        variant: p.variants[1],
        quantity: 10,
        priceOverrideCents: 1500, // negociado en mostrador
      );

      expect(line.unitPriceCents, 1500);
      expect(line.listUnitPriceCents, 1700); // lista conservada
      expect(line.hasOverride, isTrue);
      expect(line.totalCents, 15000);
    });
  });

  group('Descuento de cliente (fidelización)', () {
    final mayorista = Customer(
      id: 'c1',
      name: 'Rancho El Mezquite',
      category: CustomerCategory.mayorista,
      discountPercent: 5,
      createdAt: t0,
    );

    test('discountFor calcula el porcentaje del perfil', () {
      expect(mayorista.discountFor(200000), 10000); // 5% de $2,000
      expect(mayorista.discountFor(0), 0);
    });

    test('ticket promedio del historial', () {
      final withHistory =
          mayorista.copyWith(totalSpentCents: 300000, purchaseCount: 4);
      expect(withHistory.averageTicketCents, 75000);
    });
  });

  group('BreakVariantUseCase (desensamble)', () {
    late _FakeCatalogRepo repo;
    late BreakVariantUseCase useCase;

    setUp(() {
      repo = _FakeCatalogRepo(product());
      useCase = BreakVariantUseCase(catalog: repo);
    });

    test('valida cantidad y presentaciones', () async {
      expect(
        (await useCase(
                productId: 'p1',
                sourceVariantId: 'p1',
                targetVariantId: 'v-granel',
                quantity: 0))
            .failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await useCase(
                productId: 'p1',
                sourceVariantId: 'p1',
                targetVariantId: 'p1',
                quantity: 1))
            .failureOrNull,
        isA<ValidationFailure>(),
      );
      // Solo de mayor a menor contenido.
      expect(
        (await useCase(
                productId: 'p1',
                sourceVariantId: 'v-granel',
                targetVariantId: 'p1',
                quantity: 1))
            .failureOrNull,
        isA<ValidationFailure>(),
      );
    });

    test('rechaza sin stock suficiente', () async {
      final result = await useCase(
          productId: 'p1',
          sourceVariantId: 'p1',
          targetVariantId: 'v-granel',
          quantity: 999);

      expect(result.failureOrNull, isA<InsufficientStockFailure>());
      expect(repo.breakCalls, isEmpty);
    });

    test('camino feliz delega la conversión al repositorio', () async {
      final result = await useCase(
          productId: 'p1',
          sourceVariantId: 'p1',
          targetVariantId: 'v-granel',
          quantity: 2);

      expect(result.isOk, isTrue);
      expect(repo.breakCalls.single, ('p1', 'v-granel', 2.0));
    });
  });
}

class _FakeCatalogRepo implements CatalogRepository {
  _FakeCatalogRepo(this.item);

  final CatalogItem item;
  final breakCalls = <(String, String, double)>[];

  @override
  Future<CatalogItem?> getById(String id) async =>
      item.id == id ? item : null;

  @override
  Future<Result<double>> breakVariant(
      {required String sourceVariantId,
      required String targetVariantId,
      required double quantity}) async {
    breakCalls.add((sourceVariantId, targetVariantId, quantity));
    return Ok(quantity * 40); // costal 40 -> granel 1
  }

  @override
  Future<List<CatalogItem>> getAll({bool includeInactive = false}) async =>
      [item];

  @override
  Future<Result<CatalogItem>> save(CatalogItem item,
          {required bool isNew}) async =>
      Ok(item);

  @override
  Future<Result<void>> adjustStock(
          {required String variantId,
          required double delta,
          required String reason}) async =>
      const Ok(null);
}
