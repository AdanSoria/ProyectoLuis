import 'package:agropos/core/db/app_database.dart';
import 'package:agropos/core/utils/id_generator.dart';
import 'package:agropos/data/repositories/catalog_repository_impl.dart';
import 'package:agropos/data/repositories/customer_repository_impl.dart';
import 'package:agropos/data/repositories/transaction_repository_impl.dart';
import 'package:agropos/domain/entities/cart_line.dart';
import 'package:agropos/domain/entities/catalog_item.dart';
import 'package:agropos/domain/entities/customer.dart';
import 'package:agropos/domain/entities/delivery_person.dart';
import 'package:agropos/domain/entities/transaction.dart';
import 'package:agropos/domain/usecases/break_variant_usecase.dart';
import 'package:agropos/domain/usecases/process_transaction_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Integración de variantes + CRM contra SQLite real (en memoria).
void main() {
  late AppDatabase db;
  late TransactionRepositoryImpl transactions;
  late CatalogRepositoryImpl catalog;
  late CustomerRepositoryImpl customers;
  late ProcessTransactionUseCase processTransaction;

  const ids = UuidV4Generator();

  setUp(() async {
    db = await AppDatabase.open(overridePath: inMemoryDatabasePath);
    transactions = TransactionRepositoryImpl(db, ids);
    catalog = CatalogRepositoryImpl(db, ids);
    customers = CustomerRepositoryImpl(db, ids);
    processTransaction = ProcessTransactionUseCase(
      transactions: transactions,
      idGenerator: ids,
    );
  });

  tearDown(() => db.close());

  Future<Product> feedProduct() async {
    final items = await catalog.getAll();
    return items
        .whereType<Product>()
        .firstWhere((p) => p.name == 'Alimento para becerro');
  }

  test('vender una variante solo descuenta SU stock (con escalón aplicado)',
      () async {
    final feed = await feedProduct();
    expect(feed.hasMultipleVariants, isTrue);

    final granel = feed.sellableVariants.firstWhere((v) => v.name == 'Granel kg');
    expect(granel.stock, 20);

    // 10 kg alcanzan el escalón de volumen: $17.00/kg en vez de $18.00.
    final result = await processTransaction(ProcessTransactionInput(
      lines: [CartLine(item: feed, variant: granel, quantity: 10)],
      kind: TransactionKind.ventaMostrador,
      amountPaidCents: 17000,
    ));
    expect(result.isOk, isTrue, reason: '${result.failureOrNull}');
    expect(result.valueOrNull!.totalCents, 17000); // 10 × $17.00

    final after = await feedProduct();
    final granelAfter =
        after.sellableVariants.firstWhere((v) => v.name == 'Granel kg');
    final costalAfter =
        after.sellableVariants.firstWhere((v) => v.name == 'Costal 40 kg');
    expect(granelAfter.stock, 10); // 20 - 10
    expect(costalAfter.stock, 35); // intacto

    // La línea conserva variante y precio de lista para auditoría.
    final lineRows = await db.db.query('transaccion_lineas');
    expect(lineRows.single['variante_nombre'], 'Granel kg');
    expect(lineRows.single['precio_lista'], 1700);
  });

  test('desensamble: abrir un costal acredita el granel equivalente',
      () async {
    final feed = await feedProduct();
    final costal =
        feed.sellableVariants.firstWhere((v) => v.name == 'Costal 40 kg');
    final granel =
        feed.sellableVariants.firstWhere((v) => v.name == 'Granel kg');

    final useCase = BreakVariantUseCase(catalog: catalog);
    final result = await useCase(
      productId: feed.id,
      sourceVariantId: costal.id,
      targetVariantId: granel.id,
      quantity: 1,
    );

    expect(result.isOk, isTrue, reason: '${result.failureOrNull}');
    expect(result.valueOrNull, 40); // 1 costal de 40 kg → 40 kg granel

    final after = await feedProduct();
    expect(
        after.sellableVariants
            .firstWhere((v) => v.name == 'Costal 40 kg')
            .stock,
        34);
    expect(
        after.sellableVariants
            .firstWhere((v) => v.name == 'Granel kg')
            .stock,
        60);

    // Dos movimientos (salida y entrada) + 1 entrada de Outbox.
    final moves = await db.db.query('movimientos_inventario',
        where: "motivo = 'desensamble'");
    expect(moves, hasLength(2));
  });

  test('CRM: la venta cobrada acumula total_spent y alimenta el top',
      () async {
    final recent = await customers.getRecent(10);
    final mezquite =
        recent.firstWhere((c) => c.name == 'Rancho El Mezquite');
    expect(mezquite.category, CustomerCategory.mayorista);
    expect(mezquite.discountPercent, 5);
    expect(mezquite.totalSpentCents, 0);

    final feed = await feedProduct();
    // Venta de mostrador con cliente asignado y su 5% aplicado.
    final subtotal = feed.defaultVariant.salePriceCents; // $640.00
    final discount = mezquite.discountFor(subtotal); // $32.00
    final result = await processTransaction(ProcessTransactionInput(
      lines: [CartLine(item: feed, quantity: 1)],
      kind: TransactionKind.ventaMostrador,
      amountPaidCents: 100000,
      deductionsCents: discount,
      customer: mezquite,
    ));
    expect(result.isOk, isTrue, reason: '${result.failureOrNull}');
    expect(result.valueOrNull!.totalCents, 60800); // 640 - 5%

    final updated = (await customers.getRecent(10))
        .firstWhere((c) => c.id == mezquite.id);
    expect(updated.totalSpentCents, 60800);
    expect(updated.purchaseCount, 1);
    expect(updated.lastPurchaseAt, isNotNull);

    final top = await transactions.getTopBuyers();
    expect(top.single.name, 'Rancho El Mezquite');
    expect(top.single.totalCents, 60800);

    final byChannel = await transactions.getSalesByChannel();
    expect(byChannel.single.channelCode, 'mostrador');

    final categories = await transactions.getTopCategories();
    expect(categories.single.category, 'Alimentos');
  });

  test('un pedido acredita al cliente hasta COMPLETARSE, no antes',
      () async {
    final recent = await customers.getRecent(10);
    final granja = recent.firstWhere((c) => c.name == 'Granja Santa Fe');
    final feed = await feedProduct();

    final created = await processTransaction(ProcessTransactionInput(
      lines: [CartLine(item: feed, quantity: 2)],
      kind: TransactionKind.pedido,
      channel: SaleChannel.whatsapp,
      customer: granja,
    ));
    expect(created.isOk, isTrue);

    var current = (await customers.getRecent(10))
        .firstWhere((c) => c.id == granja.id);
    expect(current.totalSpentCents, 0); // por cobrar: aún no cuenta

    // Completar = entregar y cobrar.
    final order = created.valueOrNull!;
    final completed = await transactions.update(
      order
          .assignTo(const DeliveryPerson(id: 'rep', name: 'Repartidor moto'),
              DateTime.now())
          .completeWith(
              PaymentMethod.efectivo, order.totalCents, DateTime.now()),
      creditCustomerStats: true,
    );
    expect(completed.isOk, isTrue);

    current = (await customers.getRecent(10))
        .firstWhere((c) => c.id == granja.id);
    expect(current.totalSpentCents, order.totalCents);
    expect(current.purchaseCount, 1);
  });
}
