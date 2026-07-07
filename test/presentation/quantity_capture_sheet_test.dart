import 'package:agropos/core/db/app_database.dart';
import 'package:agropos/domain/entities/catalog_item.dart';
import 'package:agropos/domain/entities/product_variant.dart';
import 'package:agropos/presentation/providers.dart';
import 'package:agropos/presentation/screens/pos/widgets/quantity_capture_sheet.dart';
import 'package:agropos/presentation/widgets/numeric_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final t0 = DateTime.utc(2026, 6, 12);

  Product feed() => Product(
        id: 'p1',
        name: 'Alimento para becerro',
        category: 'Alimentos',
        costPriceCents: 52000,
        salePriceCents: 64000,
        unit: 'bulto',
        stock: 35,
        createdAt: t0,
        updatedAt: t0,
        variants: [
          const ProductVariant(
            id: 'p1',
            productId: 'p1',
            name: 'Costal 40 kg',
            costPriceCents: 52000,
            salePriceCents: 64000,
            stock: 35,
            unit: 'bulto',
            contentUnits: 40,
            isDefault: true,
          ),
          const ProductVariant(
            id: 'v-granel',
            productId: 'p1',
            name: 'Granel kg',
            costPriceCents: 1300,
            salePriceCents: 1800,
            stock: 20,
            unit: 'kg',
            contentUnits: 1,
            priceTiers: [PriceTier(minQuantity: 10, unitPriceCents: 1700)],
          ),
        ],
      );

  late AppDatabase db;

  setUp(() async {
    sqfliteFfiInit();
    db = await AppDatabase.open(
      overridePath: inMemoryDatabasePath,
      factoryOverride: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() => db.close());

  Future<ProviderContainer> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showQuantityCaptureSheet(context, ref, product: feed()),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('flujo de 2 toques: elegir variante granel + atajo 10 kg',
      (tester) async {
    final container = await pumpSheet(tester);

    // Elegir la presentación granel.
    await tester.tap(find.text('Granel kg · \$18.00'));
    await tester.pumpAndSettle();

    // Con costal de referencia (40 kg), el atajo "25% · 10 kg" = 10 kg,
    // que alcanza el escalón de mayoreo ($17.00).
    await tester.tap(find.text('25% · 10 kg'));
    await tester.pumpAndSettle();

    expect(find.text('Precio mayoreo aplicado'), findsOneWidget);
    expect(find.text('\$17.00 / kg'), findsOneWidget);

    await tester.tap(find.textContaining('Agregar'));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider);
    expect(cart.lines, hasLength(1));
    expect(cart.lines.single.quantity, 10);
    expect(cart.lines.single.unitPriceCents, 1700);
    // Recordó la variante para la próxima vez.
    expect(container.read(lastVariantByProductProvider)['p1'], 'v-granel');
  });

  testWidgets('teclado numérico propio compone la cantidad', (tester) async {
    final container = await pumpSheet(tester);

    // Sin abrir teclado del sistema: usar el numpad (2 y 5 → "25").
    Finder key(String d) => find.descendant(
        of: find.byType(NumericKeypad), matching: find.text(d));
    await tester.tap(key('2'));
    await tester.pumpAndSettle();
    await tester.tap(key('5'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Agregar'));
    await tester.pumpAndSettle();

    // Variante default (costal) × 25.
    expect(container.read(cartProvider).lines.single.quantity, 25);
  });
}
