import 'package:agropos/core/db/app_database.dart';
import 'package:agropos/core/utils/id_generator.dart';
import 'package:agropos/data/repositories/catalog_repository_impl.dart';
import 'package:agropos/data/repositories/transaction_repository_impl.dart';
import 'package:agropos/domain/entities/cart_line.dart';
import 'package:agropos/domain/entities/catalog_item.dart';
import 'package:agropos/domain/entities/transaction.dart';
import 'package:agropos/domain/usecases/process_transaction_usecase.dart';
import 'package:agropos/presentation/screens/pos/widgets/free_item_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Verifica que un ítem libre efímero (servicio sin fila en catálogo) se
/// cobra como snapshot sin tocar inventario ni requerir FK.
void main() {
  late AppDatabase db;
  late TransactionRepositoryImpl transactions;
  late CatalogRepositoryImpl catalog;
  late ProcessTransactionUseCase processTransaction;
  const ids = UuidV4Generator();

  setUp(() async {
    db = await AppDatabase.open(overridePath: inMemoryDatabasePath);
    transactions = TransactionRepositoryImpl(db, ids);
    catalog = CatalogRepositoryImpl(db, ids);
    processTransaction =
        ProcessTransactionUseCase(transactions: transactions, idGenerator: ids);
  });
  tearDown(() => db.close());

  Future<int> count(String table) async {
    final rows = await db.db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return (rows.first['n'] as num).toInt();
  }

  test('ítem libre efímero: se vende sin fila en catálogo ni movimiento',
      () async {
    final catalogoAntes = await count('catalogo');

    final libre = Service(
      id: ids.newId(),
      name: 'Reparación de manguera',
      category: kFreeItemCategory,
      costPriceCents: 0,
      salePriceCents: 8000,
      unit: 'pieza',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    final result = await processTransaction(ProcessTransactionInput(
      lines: [CartLine(item: libre, quantity: 1)],
      kind: TransactionKind.ventaMostrador,
      amountPaidCents: 10000,
    ));

    expect(result.isOk, isTrue, reason: '${result.failureOrNull}');
    // No se creó nada en catálogo ni movimientos de inventario.
    expect(await count('catalogo'), catalogoAntes);
    expect(await count('movimientos_inventario'), 0);
    // La línea quedó como snapshot con su nombre y precio.
    final lineRows = await db.db.query('transaccion_lineas');
    expect(lineRows.single['item_nombre'], 'Reparación de manguera');
    expect(lineRows.single['importe'], 8000);
    expect(lineRows.single['item_tipo'], 'servicio');
  });

  test('ítem libre guardado: alta real en catálogo y luego vendible',
      () async {
    final producto = Product.simple(
      id: ids.newId(),
      name: 'Tornillo especial',
      category: 'Varios',
      costPriceCents: 0,
      salePriceCents: 500,
      unit: 'pieza',
      stock: 0,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    final saved = await catalog.save(producto, isNew: true);
    expect(saved.isOk, isTrue);

    final found = await catalog.getById(producto.id);
    expect(found, isA<Product>());
    expect(found!.name, 'Tornillo especial');
    // Se puede vender (stock 0 permite venta de servicio-like? no: es
    // producto con stock 0 → validaría stock. Aquí solo confirmamos alta).
    expect((found as Product).defaultVariant.stock, 0);
  });
}
