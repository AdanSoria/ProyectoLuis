import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/id_generator.dart';

/// Punto único de acceso a SQLite. Crea el esquema, siembra datos de
/// demostración en el primer arranque y expone utilidades llave-valor
/// (borrador del carrito, identificador del dispositivo).
class AppDatabase {
  AppDatabase._(this.db, this.deviceId);

  final Database db;

  /// Identificador UUID v4 de este dispositivo, generado una sola vez.
  /// Viaja en cada lote de sincronización para auditoría multi-sucursal.
  final String deviceId;

  static const int _schemaVersion = 2;

  static Future<AppDatabase> open({
    String? overridePath,
    DatabaseFactory? factoryOverride,
  }) async {
    if (factoryOverride != null) {
      // Pruebas: permite inyectar p. ej. databaseFactoryFfiNoIsolate,
      // necesario porque los testWidgets corren en zona fake-async.
      databaseFactory = factoryOverride;
    } else if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      // En escritorio (Windows/Linux/macOS) sqflite usa la implementación FFI.
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String path;
    if (overridePath != null) {
      path = overridePath;
    } else {
      final dir = await getApplicationSupportDirectory();
      path = p.join(dir.path, 'agropos.db');
    }

    final db = await openDatabase(
      path,
      version: _schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seedDemoData(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _migrateV1toV2(db);
      },
    );

    final deviceId = await _ensureDeviceId(db);
    return AppDatabase._(db, deviceId);
  }

  // ---------------------------------------------------------------- esquema

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE catalogo(
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        categoria TEXT NOT NULL,
        unidad TEXT NOT NULL DEFAULT 'pieza',
        precio_costo INTEGER NOT NULL DEFAULT 0,
        precio_venta INTEGER NOT NULL DEFAULT 0,
        stock REAL,
        activo INTEGER NOT NULL DEFAULT 1,
        creado_en TEXT NOT NULL,
        actualizado_en TEXT NOT NULL
      )
    ''');

    // Variantes (SKUs): cada presentación tiene precio y stock propios.
    // La variante default de un producto comparte su mismo id.
    await db.execute('''
      CREATE TABLE variantes(
        id TEXT PRIMARY KEY,
        producto_id TEXT NOT NULL REFERENCES catalogo(id),
        nombre TEXT NOT NULL,
        sku TEXT,
        precio_costo INTEGER NOT NULL DEFAULT 0,
        precio_venta INTEGER NOT NULL DEFAULT 0,
        stock REAL NOT NULL DEFAULT 0,
        unidad TEXT NOT NULL DEFAULT 'pieza',
        contenido REAL NOT NULL DEFAULT 1,
        es_default INTEGER NOT NULL DEFAULT 0,
        activo INTEGER NOT NULL DEFAULT 1,
        precios_volumen TEXT,
        creado_en TEXT NOT NULL,
        actualizado_en TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE clientes(
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        telefono TEXT,
        notas TEXT,
        categoria TEXT NOT NULL DEFAULT 'minorista',
        descuento_pct REAL NOT NULL DEFAULT 0,
        total_gastado INTEGER NOT NULL DEFAULT 0,
        compras INTEGER NOT NULL DEFAULT 0,
        ultima_compra TEXT,
        creado_en TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE repartidores(
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        telefono TEXT,
        activo INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE transacciones(
        id TEXT PRIMARY KEY,
        folio TEXT NOT NULL,
        tipo TEXT NOT NULL,
        canal TEXT NOT NULL,
        estado TEXT NOT NULL,
        cliente_id TEXT,
        cliente_nombre TEXT,
        cliente_telefono TEXT,
        repartidor_id TEXT,
        repartidor_nombre TEXT,
        metodo_pago TEXT NOT NULL,
        monto_recibido INTEGER NOT NULL DEFAULT 0,
        subtotal INTEGER NOT NULL,
        deducciones INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL,
        precio_costo_total INTEGER NOT NULL,
        utilidad_neta INTEGER NOT NULL,
        notas TEXT,
        creado_en TEXT NOT NULL,
        actualizado_en TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE transaccion_lineas(
        id TEXT PRIMARY KEY,
        transaccion_id TEXT NOT NULL REFERENCES transacciones(id),
        item_id TEXT NOT NULL,
        item_nombre TEXT NOT NULL,
        item_tipo TEXT NOT NULL,
        cantidad REAL NOT NULL,
        precio_venta INTEGER NOT NULL,
        precio_costo INTEGER NOT NULL,
        importe INTEGER NOT NULL,
        costo INTEGER NOT NULL,
        variante_id TEXT,
        variante_nombre TEXT,
        precio_lista INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE movimientos_inventario(
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL,
        delta REAL NOT NULL,
        motivo TEXT NOT NULL,
        transaccion_id TEXT,
        variante_id TEXT,
        creado_en TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue(
        id TEXT PRIMARY KEY,
        entidad TEXT NOT NULL,
        entidad_id TEXT NOT NULL,
        operacion TEXT NOT NULL,
        payload TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'pendiente',
        intentos INTEGER NOT NULL DEFAULT 0,
        ultimo_error TEXT,
        proximo_intento TEXT,
        creado_en TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE TABLE kv_store(k TEXT PRIMARY KEY, v TEXT NOT NULL)');

    await db.execute('CREATE INDEX idx_txn_estado ON transacciones(estado)');
    await db.execute('CREATE INDEX idx_txn_creado ON transacciones(creado_en)');
    await db.execute('CREATE INDEX idx_sync_estado ON sync_queue(estado)');
    await db
        .execute('CREATE INDEX idx_lineas_txn ON transaccion_lineas(transaccion_id)');
    await db
        .execute('CREATE INDEX idx_variantes_producto ON variantes(producto_id)');
  }

  /// v1 → v2: variantes (SKUs), perfil CRM del cliente y columnas de
  /// auditoría de regateo. Cada producto existente recibe su variante
  /// default reutilizando su mismo uuid — nada se pierde ni se duplica.
  static Future<void> _migrateV1toV2(Database db) async {
    await db.execute(
        "ALTER TABLE clientes ADD COLUMN categoria TEXT NOT NULL DEFAULT 'minorista'");
    await db.execute(
        'ALTER TABLE clientes ADD COLUMN descuento_pct REAL NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE clientes ADD COLUMN total_gastado INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE clientes ADD COLUMN compras INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE clientes ADD COLUMN ultima_compra TEXT');

    await db.execute('''
      CREATE TABLE variantes(
        id TEXT PRIMARY KEY,
        producto_id TEXT NOT NULL REFERENCES catalogo(id),
        nombre TEXT NOT NULL,
        sku TEXT,
        precio_costo INTEGER NOT NULL DEFAULT 0,
        precio_venta INTEGER NOT NULL DEFAULT 0,
        stock REAL NOT NULL DEFAULT 0,
        unidad TEXT NOT NULL DEFAULT 'pieza',
        contenido REAL NOT NULL DEFAULT 1,
        es_default INTEGER NOT NULL DEFAULT 0,
        activo INTEGER NOT NULL DEFAULT 1,
        precios_volumen TEXT,
        creado_en TEXT NOT NULL,
        actualizado_en TEXT NOT NULL
      )
    ''');
    await db
        .execute('CREATE INDEX idx_variantes_producto ON variantes(producto_id)');

    await db.execute('''
      INSERT INTO variantes(id, producto_id, nombre, sku, precio_costo,
        precio_venta, stock, unidad, contenido, es_default, activo,
        precios_volumen, creado_en, actualizado_en)
      SELECT id, id, 'Estándar', NULL, precio_costo, precio_venta,
        COALESCE(stock, 0), unidad, 1, 1, activo, NULL, creado_en,
        actualizado_en
      FROM catalogo WHERE tipo = 'producto'
    ''');

    await db
        .execute('ALTER TABLE transaccion_lineas ADD COLUMN variante_id TEXT');
    await db.execute(
        'ALTER TABLE transaccion_lineas ADD COLUMN variante_nombre TEXT');
    await db.execute(
        'ALTER TABLE transaccion_lineas ADD COLUMN precio_lista INTEGER');
    await db.execute(
        'ALTER TABLE movimientos_inventario ADD COLUMN variante_id TEXT');
  }

  // ----------------------------------------------------- datos de arranque

  /// Catálogo de demostración (insumos agrícolas, veterinaria y servicios)
  /// para que el punto de venta sea usable desde el primer arranque.
  static Future<void> _seedDemoData(Database db) async {
    const ids = UuidV4Generator();
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = db.batch();

    void variant(String productoId, String id, String nombre, String unidad,
        int costo, int venta, double stock, double contenido, bool esDefault,
        {String? preciosVolumen}) {
      batch.insert('variantes', {
        'id': id,
        'producto_id': productoId,
        'nombre': nombre,
        'sku': null,
        'precio_costo': costo,
        'precio_venta': venta,
        'stock': stock,
        'unidad': unidad,
        'contenido': contenido,
        'es_default': esDefault ? 1 : 0,
        'activo': 1,
        'precios_volumen': preciosVolumen,
        'creado_en': now,
        'actualizado_en': now,
      });
    }

    /// Producto simple: una variante default que comparte su uuid.
    String product(String nombre, String categoria, String unidad, int costo,
        int venta, double stock) {
      final id = ids.newId();
      batch.insert('catalogo', {
        'id': id,
        'tipo': 'producto',
        'nombre': nombre,
        'categoria': categoria,
        'unidad': unidad,
        'precio_costo': costo,
        'precio_venta': venta,
        'stock': stock,
        'activo': 1,
        'creado_en': now,
        'actualizado_en': now,
      });
      variant(id, id, 'Estándar', unidad, costo, venta, stock, 1, true);
      return id;
    }

    void service(String nombre, String categoria, int costo, int venta) {
      batch.insert('catalogo', {
        'id': ids.newId(),
        'tipo': 'servicio',
        'nombre': nombre,
        'categoria': categoria,
        'unidad': 'servicio',
        'precio_costo': costo,
        'precio_venta': venta,
        'stock': null,
        'activo': 1,
        'creado_en': now,
        'actualizado_en': now,
      });
    }

    // Precios en centavos.
    product('Semilla de maíz híbrido 20 kg', 'Semillas', 'bulto', 145000, 175000, 24);
    product('Semilla de sorgo 20 kg', 'Semillas', 'bulto', 98000, 119000, 15);
    product('Fertilizante triple 17 50 kg', 'Fertilizantes', 'bulto', 78000, 95000, 40);
    product('Urea 46% 50 kg', 'Fertilizantes', 'bulto', 69000, 84000, 32);
    product('Sal mineral 25 kg', 'Alimentos', 'bulto', 31000, 42000, 26);
    product('Vacuna triple bovina', 'Veterinaria', 'frasco', 9500, 15000, 60);
    product('Desparasitante oral 1 L', 'Veterinaria', 'litro', 18000, 26000, 18);
    product('Herbicida 1 L', 'Agroquímicos', 'litro', 12000, 18500, 30);
    product('Rollo alambre de púas 34 kg', 'Ferretería', 'rollo', 99000, 119000, 12);

    // Producto con variantes: costal completo (mayoreo) y granel por kg
    // (menudeo, más caro por unidad, con escalón de volumen a 10+ kg).
    final alimentoId = ids.newId();
    batch.insert('catalogo', {
      'id': alimentoId,
      'tipo': 'producto',
      'nombre': 'Alimento para becerro',
      'categoria': 'Alimentos',
      'unidad': 'bulto',
      'precio_costo': 52000,
      'precio_venta': 64000,
      'stock': 35,
      'activo': 1,
      'creado_en': now,
      'actualizado_en': now,
    });
    variant(alimentoId, alimentoId, 'Costal 40 kg', 'bulto', 52000, 64000, 35,
        40, true);
    variant(alimentoId, ids.newId(), 'Granel kg', 'kg', 1300, 1800, 20, 1,
        false,
        preciosVolumen: '[{"min":10,"precio":1700}]');

    service('Flete local', 'Servicios', 6000, 15000);
    service('Consulta veterinaria', 'Servicios', 0, 25000);
    service('Aplicación de vacuna a domicilio', 'Servicios', 4000, 12000);

    // Repartidores genéricos (sin nombres de personas reales).
    batch.insert('repartidores',
        {'id': ids.newId(), 'nombre': 'Repartidor moto', 'telefono': null, 'activo': 1});
    batch.insert('repartidores', {
      'id': ids.newId(),
      'nombre': 'Repartidor camioneta',
      'telefono': null,
      'activo': 1
    });

    // Clientes frecuentes de ejemplo (uno mayorista con descuento base).
    batch.insert('clientes', {
      'id': ids.newId(),
      'nombre': 'Rancho El Mezquite',
      'telefono': '5550000001',
      'notas': null,
      'categoria': 'mayorista',
      'descuento_pct': 5,
      'total_gastado': 0,
      'compras': 0,
      'ultima_compra': null,
      'creado_en': now,
    });
    batch.insert('clientes', {
      'id': ids.newId(),
      'nombre': 'Granja Santa Fe',
      'telefono': '5550000002',
      'notas': null,
      'categoria': 'minorista',
      'descuento_pct': 0,
      'total_gastado': 0,
      'compras': 0,
      'ultima_compra': null,
      'creado_en': now,
    });

    await batch.commit(noResult: true);
  }

  static Future<String> _ensureDeviceId(Database db) async {
    final rows = await db
        .query('kv_store', where: 'k = ?', whereArgs: ['device_id'], limit: 1);
    if (rows.isNotEmpty) return rows.first['v']! as String;

    final id = const UuidV4Generator().newId();
    await db.insert('kv_store', {'k': 'device_id', 'v': id});
    return id;
  }

  // ------------------------------------------------------------ llave-valor

  Future<String?> getKv(String key) async {
    final rows =
        await db.query('kv_store', where: 'k = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }

  Future<void> setKv(String key, String value) => db.insert(
        'kv_store',
        {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> close() => db.close();
}
