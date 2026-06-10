import 'dart:convert';
import 'dart:typed_data';

import 'package:agropos/data/import/table_file_reader.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reader = TableFileReader();

  Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

  group('CSV', () {
    test('separado por comas', () {
      final table = reader.read(
        fileName: 'productos.csv',
        bytes: bytesOf('Nombre,Precio,Stock\nMaíz híbrido,1750.50,24\n'),
      );

      expect(table.headers, ['Nombre', 'Precio', 'Stock']);
      expect(table.rows.single, ['Maíz híbrido', '1750.50', '24']);
    });

    test('separado por punto y coma, con BOM y saltos de Windows (Excel es-MX)',
        () {
      const csv = '﻿Nombre;Precio venta;Existencias\r\n'
          'Urea 46%;840;32\r\n'
          'Flete local;150;\r\n';
      final table =
          reader.read(fileName: 'CATALOGO.CSV', bytes: bytesOf(csv));

      expect(table.headers, ['Nombre', 'Precio venta', 'Existencias']);
      expect(table.rows, hasLength(2));
      expect(table.rows.first, ['Urea 46%', '840', '32']);
      expect(table.rows.last, ['Flete local', '150', '']);
    });

    test('campos entrecomillados con comas internas', () {
      final table = reader.read(
        fileName: 'x.csv',
        bytes: bytesOf('Nombre,Nota\n"Alambre, rollo 34 kg","Pasillo 2, alto"\n'),
      );

      expect(table.rows.single, ['Alambre, rollo 34 kg', 'Pasillo 2, alto']);
    });

    test('filas disparejas se rellenan al ancho del encabezado', () {
      final table = reader.read(
        fileName: 'x.csv',
        bytes: bytesOf('A,B,C\n1,2\n4,5,6,7\n'),
      );

      expect(table.rows.first, ['1', '2', '']);
      expect(table.rows.last, ['4', '5', '6']);
    });
  });

  group('XLSX', () {
    test('round-trip: lee texto, enteros y decimales como texto plano', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.appendRow([
        TextCellValue('Nombre'),
        TextCellValue('Precio'),
        TextCellValue('Stock'),
      ]);
      sheet.appendRow([
        TextCellValue('Vacuna triple'),
        const DoubleCellValue(150.5),
        const IntCellValue(60),
      ]);
      sheet.appendRow([
        TextCellValue('Sal mineral'),
        const DoubleCellValue(420), // entero guardado como double
        null,
      ]);
      final bytes = Uint8List.fromList(excel.encode()!);

      final table = reader.read(fileName: 'catalogo.xlsx', bytes: bytes);

      expect(table.headers, ['Nombre', 'Precio', 'Stock']);
      expect(table.rows.first, ['Vacuna triple', '150.5', '60']);
      // 420.0 se normaliza a "420" y la celda vacía a ''.
      expect(table.rows.last, ['Sal mineral', '420', '']);
    });
  });

  test('extensión no soportada lanza FormatException con instrucción', () {
    expect(
      () => reader.read(fileName: 'viejo.xls', bytes: bytesOf('x')),
      throwsA(isA<FormatException>()),
    );
  });
}
