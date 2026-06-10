import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
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

  static const int _schemaVersion = 1;

  static Future<AppDatabase> open({String? overridePath}) async {
    // En escritorio (Windows/Linux/macOS) sqflite usa la implementación FFI.
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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

    await db.execute('''
      CREATE TABLE clientes(
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        telefono TEXT,
        notas TEXT,
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
        costo INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE movimientos_inventario(
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL,
        delta REAL NOT NULL,
        motivo TEXT NOT NULL,
        transaccion_id TEXT,
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
  }

  // ----------------------------------------------------- datos de arranque

  /// Catálogo de demostración (insumos agrícolas, veterinaria y servicios)
  /// para que el punto de venta sea usable desde el primer arranque.
  static Future<void> _seedDemoData(Database db) async {
    const ids = UuidV4Generator();
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = db.batch();

    void product(String nombre, String categoria, String unidad, int costo,
        int venta, double stock) {
      batch.insert('catalogo', {
        'id': ids.newId(),
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
    product('Alimento para becerro 40 kg', 'Alimentos', 'bulto', 52000, 64000, 35);
    product('Sal mineral 25 kg', 'Alimentos', 'bulto', 31000, 42000, 26);
    product('Vacuna triple bovina', 'Veterinaria', 'frasco', 9500, 15000, 60);
    product('Desparasitante oral 1 L', 'Veterinaria', 'litro', 18000, 26000, 18);
    product('Herbicida 1 L', 'Agroquímicos', 'litro', 12000, 18500, 30);
    product('Rollo alambre de púas 34 kg', 'Ferretería', 'rollo', 99000, 119000, 12);

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

    // Clientes frecuentes de ejemplo.
    batch.insert('clientes', {
      'id': ids.newId(),
      'nombre': 'Rancho El Mezquite',
      'telefono': '5550000001',
      'notas': null,
      'creado_en': now,
    });
    batch.insert('clientes', {
      'id': ids.newId(),
      'nombre': 'Granja Santa Fe',
      'telefono': '5550000002',
      'notas': null,
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
