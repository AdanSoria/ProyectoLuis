import 'package:agropos/core/db/app_database.dart';
import 'package:agropos/core/errors/failures.dart';
import 'package:agropos/core/utils/id_generator.dart';
import 'package:agropos/data/repositories/catalog_repository_impl.dart';
import 'package:agropos/data/repositories/sync_queue_repository_impl.dart';
import 'package:agropos/data/repositories/transaction_repository_impl.dart';
import 'package:agropos/domain/entities/cart_line.dart';
import 'package:agropos/domain/entities/catalog_item.dart';
import 'package:agropos/domain/entities/transaction.dart';
import 'package:agropos/domain/usecases/cancel_order_usecase.dart';
import 'package:agropos/domain/usecases/process_transaction_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Integración contra SQLite real (en memoria): verifica la atomicidad
/// de venta + descuento de stock + movimientos + Outbox.
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
    processTransaction = ProcessTransactionUseCase(
      transactions: transactions,
      idGenerator: ids,
    );
  });

  tearDown(() => db.close());

  Future<Product> productByName(String name) async {
    final items = await catalog.getAll();
    return items.whereType<Product>().firstWhere((p) => p.name == name);
  }

  Future<Service> serviceByName(String name) async {
    final items = await catalog.getAll();
    return items.whereType<Service>().firstWhere((s) => s.name == name);
  }

  Future<int> count(String table) async {
    final rows = await db.db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return (rows.first['n'] as num).toInt();
  }

  test('venta de mostrador: descuenta stock, registra movimiento y encola',
      () async {
    final herbicide = await productByName('Herbicida 1 L');
    final flete = await serviceByName('Flete local');
    expect(herbicide.stock, 30);

    final result = await processTransaction(ProcessTransactionInput(
      lines: [
        CartLine(item: herbicide, quantity: 2),
        CartLine(item: flete, quantity: 1),
      ],
      kind: TransactionKind.ventaMostrador,
      amountPaidCents: 60000,
    ));

    expect(result.isOk, isTrue, reason: '${result.failureOrNull}');

    // Stock del producto descontado; el servicio no toca inventario.
    final after = await productByName('Herbicida 1 L');
    expect(after.stock, 28);

    // utilidad_neta persistida = (2×185 + 150) − (2×120 + 60) = 220.00
    final saved = await db.db.query('transacciones');
    expect(saved, hasLength(1));
    expect(saved.first['total'], 52000);
    expect(saved.first['utilidad_neta'], 22000);

    expect(await count('transaccion_lineas'), 2);
    expect(await count('movimientos_inventario'), 1); // solo el producto
    expect(await count('sync_queue'), 1); // Outbox en la misma transacción
  });

  test('stock insuficiente: rechaza y NO deja rastros a medias', () async {
    final herbicide = await productByName('Herbicida 1 L');

    final result = await processTransaction(ProcessTransactionInput(
      lines: [CartLine(item: herbicide, quantity: 999)],
      kind: TransactionKind.ventaMostrador,
      amountPaidCents: 99999900,
    ));

    expect(result.failureOrNull, isA<InsufficientStockFailure>());

    final after = await productByName('Herbicida 1 L');
    expect(after.stock, 30); // intacto
    expect(await count('transacciones'), 0);
    expect(await count('movimientos_inventario'), 0);
    expect(await count('sync_queue'), 0);
  });

  test('cancelar un pedido devuelve el stock al inventario', () async {
    final feed = await productByName('Alimento para becerro 40 kg');
    expect(feed.stock, 35);

    final created = await processTransaction(ProcessTransactionInput(
      lines: [CartLine(item: feed, quantity: 5)],
      kind: TransactionKind.pedido,
      channel: SaleChannel.whatsapp,
      customerName: 'Rancho La Loma',
    ));
    expect(created.isOk, isTrue);
    expect((await productByName('Alimento para becerro 40 kg')).stock, 30);

    final cancel = CancelOrderUseCase(transactions: transactions);
    final cancelled = await cancel(orderId: created.valueOrNull!.id);

    expect(cancelled.isOk, isTrue, reason: '${cancelled.failureOrNull}');
    expect(cancelled.valueOrNull!.status, OrderStatus.cancelado);
    expect((await productByName('Alimento para becerro 40 kg')).stock, 35);

    // Movimientos: salida del pedido + reposición por cancelación.
    expect(await count('movimientos_inventario'), 2);
    // Outbox: create del pedido + update de la cancelación.
    expect(await count('sync_queue'), 2);
  });

  test('Outbox: takeBatch marca en vuelo, markFailed agenda backoff',
      () async {
    final herbicide = await productByName('Herbicida 1 L');
    await processTransaction(ProcessTransactionInput(
      lines: [CartLine(item: herbicide, quantity: 1)],
      kind: TransactionKind.ventaMostrador,
      amountPaidCents: 18500,
    ));

    final queue = SyncQueueRepositoryImpl(db);
    expect(await queue.pendingCount(), 1);

    final now = DateTime.now();
    final batch = await queue.takeBatch(10, now: now);
    expect(batch, hasLength(1));

    // Mientras está "enviando", otro ciclo no la toma.
    expect(await queue.takeBatch(10, now: now), isEmpty);

    // Falla: vuelve a pendiente con reintento agendado en el futuro,
    // así que un takeBatch inmediato tampoco la toma…
    await queue.markFailed(batch.single.id, 'HTTP 500', now: now);
    expect(await queue.takeBatch(10, now: now), isEmpty);

    // …pero sí cuando el backoff ya venció.
    final later = now.add(const Duration(minutes: 5));
    expect(await queue.takeBatch(10, now: later), hasLength(1));

    expect(await queue.pendingCount(), 1); // nunca se perdió
  });
}
