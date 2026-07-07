import 'package:agropos/core/db/app_database.dart';
import 'package:agropos/domain/entities/catalog_item.dart';
import 'package:agropos/presentation/providers.dart';
import 'package:agropos/presentation/screens/pos/widgets/ticket_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final t0 = DateTime.utc(2026, 6, 12);
  late AppDatabase db;

  setUp(() async {
    sqfliteFfiInit();
    db = await AppDatabase.open(
      overridePath: inMemoryDatabasePath,
      factoryOverride: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() => db.close());

  Product item() => Product.simple(
        id: 'p1',
        name: 'Urea 46%',
        category: 'Fertilizantes',
        costPriceCents: 69000,
        salePriceCents: 84000,
        unit: 'bulto',
        stock: 30,
        createdAt: t0,
        updatedAt: t0,
      );

  testWidgets('la barra de acciones muestra Cliente/Descuento/Ítem libre',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    container.read(cartProvider.notifier).add(item());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 380, child: TicketPanel())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Las tres acciones están visibles en una sola barra.
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('Descuento'), findsOneWidget);
    expect(find.text('Ítem libre'), findsOneWidget);
    // El total del ítem agregado se muestra.
    expect(find.text('\$840.00'), findsWidgets);
    // Transparencia de precio: la línea a precio de lista muestra "Lista".
    expect(find.text('Lista'), findsOneWidget);

    // Tocar "Ítem libre" abre su diálogo.
    await tester.tap(find.text('Ítem libre'));
    await tester.pumpAndSettle();
    expect(find.text('Cobra algo que no está en el catálogo.'), findsOneWidget);
  });
}
