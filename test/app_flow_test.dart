import 'package:agropos/app.dart';
import 'package:agropos/core/db/app_database.dart';
import 'package:agropos/core/network/connectivity_service.dart';
import 'package:agropos/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _OfflineConnectivity implements ConnectivityService {
  @override
  Future<bool> hasConnection() async => false;

  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}

/// Prueba de extremo a extremo: arranca la app real con SQLite en memoria
/// y ejecuta una venta de mostrador completa de fricción cero.
void main() {
  testWidgets('venta completa: tap al producto, COBRAR y confirmar',
      (tester) async {
    // Pantalla de escritorio: activa el split-screen catálogo + ticket.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = await AppDatabase.open(
      overridePath: inMemoryDatabasePath,
      // Sin isolate: las respuestas de SQLite avanzan bajo fake-async.
      factoryOverride: databaseFactoryFfiNoIsolate,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          connectivityServiceProvider
              .overrideWithValue(_OfflineConnectivity()),
        ],
        child: const AgroPosApp(),
      ),
    );
    await tester.pumpAndSettle();

    // El catálogo sembrado está en pantalla.
    expect(find.text('Herbicida 1 L'), findsOneWidget);

    // 1 toque = al carrito; aparece también en el ticket.
    await tester.tap(find.text('Herbicida 1 L'));
    await tester.pumpAndSettle();
    expect(find.text('Herbicida 1 L'), findsNWidgets(2));
    expect(find.text(r'$185.00'), findsWidgets);

    // Cobro en 2 toques: COBRAR -> CONFIRMAR (monto exacto precargado).
    await tester.tap(find.text('COBRAR'));
    await tester.pumpAndSettle();
    expect(find.text('CONFIRMAR COBRO'), findsOneWidget);

    await tester.tap(find.text('CONFIRMAR COBRO'));
    await tester.pumpAndSettle();

    // Venta registrada: folio en el SnackBar y carrito vacío.
    expect(find.textContaining('cobrada'), findsOneWidget);
    expect(find.textContaining('Toca un producto'), findsOneWidget);

    // El inventario bajó y la operación quedó encolada para sincronizar.
    final stock = await db.db.query('catalogo',
        columns: ['stock'],
        where: 'nombre = ?',
        whereArgs: ['Herbicida 1 L']);
    expect((stock.single['stock'] as num).toDouble(), 29);

    final queued =
        await db.db.rawQuery('SELECT COUNT(*) AS n FROM sync_queue');
    expect((queued.first['n'] as num).toInt(), 1);

    // Deja expirar el SnackBar y desmonta para liberar timers y la base.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await db.close();
  });
}
