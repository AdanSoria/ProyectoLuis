import 'dart:io';

import 'package:agropos/core/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Verifica que abrir una base creada con el esquema v1 (sin variantes
/// ni perfil CRM) migra a v2 SIN perder datos: cada producto recibe su
/// variante default (mismo uuid) y los clientes sus columnas nuevas.
void main() {
  late String path;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('agropos_migration');
    path = '${dir.path}/v1.db';
  });

  tearDown(() async {
    final file = File(path);
    if (file.existsSync()) await file.parent.delete(recursive: true);
  });

  Future<void> createV1Database() async {
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          // Esquema v1 tal como existía antes de variantes/CRM.
          await db.execute('''
            CREATE TABLE catalogo(
              id TEXT PRIMARY KEY, tipo TEXT NOT NULL, nombre TEXT NOT NULL,
              categoria TEXT NOT NULL, unidad TEXT NOT NULL DEFAULT 'pieza',
              precio_costo INTEGER NOT NULL DEFAULT 0,
              precio_venta INTEGER NOT NULL DEFAULT 0,
              stock REAL, activo INTEGER NOT NULL DEFAULT 1,
              creado_en TEXT NOT NULL, actualizado_en TEXT NOT NULL)
          ''');
          await db.execute('''
            CREATE TABLE clientes(
              id TEXT PRIMARY KEY, nombre TEXT NOT NULL, telefono TEXT,
              notas TEXT, creado_en TEXT NOT NULL)
          ''');
          await db.execute('''
            CREATE TABLE transaccion_lineas(
              id TEXT PRIMARY KEY, transaccion_id TEXT NOT NULL,
              item_id TEXT NOT NULL, item_nombre TEXT NOT NULL,
              item_tipo TEXT NOT NULL, cantidad REAL NOT NULL,
              precio_venta INTEGER NOT NULL, precio_costo INTEGER NOT NULL,
              importe INTEGER NOT NULL, costo INTEGER NOT NULL)
          ''');
          await db.execute('''
            CREATE TABLE movimientos_inventario(
              id TEXT PRIMARY KEY, item_id TEXT NOT NULL, delta REAL NOT NULL,
              motivo TEXT NOT NULL, transaccion_id TEXT, creado_en TEXT NOT NULL)
          ''');
          await db.execute(
              'CREATE TABLE kv_store(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
          await db.execute('''
            CREATE TABLE sync_queue(
              id TEXT PRIMARY KEY, entidad TEXT NOT NULL,
              entidad_id TEXT NOT NULL, operacion TEXT NOT NULL,
              payload TEXT NOT NULL, estado TEXT NOT NULL DEFAULT 'pendiente',
              intentos INTEGER NOT NULL DEFAULT 0, ultimo_error TEXT,
              proximo_intento TEXT, creado_en TEXT NOT NULL)
          ''');

          const now = '2026-01-01T00:00:00.000Z';
          await db.insert('catalogo', {
            'id': 'prod-legacy',
            'tipo': 'producto',
            'nombre': 'Costal de Luis 50 kg',
            'categoria': 'Alimentos',
            'unidad': 'bulto',
            'precio_costo': 80000,
            'precio_venta': 99000,
            'stock': 17,
            'activo': 1,
            'creado_en': now,
            'actualizado_en': now,
          });
          await db.insert('catalogo', {
            'id': 'serv-legacy',
            'tipo': 'servicio',
            'nombre': 'Flete viejo',
            'categoria': 'Servicios',
            'unidad': 'servicio',
            'precio_costo': 0,
            'precio_venta': 12000,
            'stock': null,
            'activo': 1,
            'creado_en': now,
            'actualizado_en': now,
          });
          await db.insert('clientes', {
            'id': 'cli-legacy',
            'nombre': 'Cliente Viejo',
            'telefono': '5551112222',
            'notas': null,
            'creado_en': now,
          });
        },
      ),
    );
    await db.close();
  }

  test('v1 -> v2 conserva productos, crea variantes default y perfila clientes',
      () async {
    await createV1Database();

    // Reabrir con la app actual dispara onUpgrade.
    final app = await AppDatabase.open(overridePath: path);
    addTearDown(app.close);

    // El producto legado sigue ahí y su variante default comparte uuid.
    final variants = await app.db
        .query('variantes', where: 'producto_id = ?', whereArgs: ['prod-legacy']);
    expect(variants, hasLength(1));
    expect(variants.single['id'], 'prod-legacy');
    expect(variants.single['es_default'], 1);
    expect((variants.single['stock'] as num).toDouble(), 17);
    expect(variants.single['precio_venta'], 99000);
    expect((variants.single['contenido'] as num).toDouble(), 1);

    // Los servicios NO generan variantes.
    final serviceVariants = await app.db.query('variantes',
        where: 'producto_id = ?', whereArgs: ['serv-legacy']);
    expect(serviceVariants, isEmpty);

    // El cliente legado recibe su perfil CRM con defaults seguros.
    final clients = await app.db
        .query('clientes', where: 'id = ?', whereArgs: ['cli-legacy']);
    expect(clients.single['categoria'], 'minorista');
    expect((clients.single['descuento_pct'] as num).toDouble(), 0);
    expect(clients.single['total_gastado'], 0);
    expect(clients.single['compras'], 0);

    // Las columnas nuevas de líneas/movimientos existen (insertable).
    await app.db.insert('movimientos_inventario', {
      'id': 'mv-1',
      'item_id': 'prod-legacy',
      'variante_id': 'prod-legacy',
      'delta': 1,
      'motivo': 'ajuste_manual',
      'transaccion_id': null,
      'creado_en': '2026-06-12T00:00:00.000Z',
    });

    // Y la app NO re-siembra datos demo sobre una base migrada.
    final productCount = await app.db
        .rawQuery("SELECT COUNT(*) AS n FROM catalogo WHERE tipo='producto'");
    expect(productCount.first['n'], 1);
  });
}
