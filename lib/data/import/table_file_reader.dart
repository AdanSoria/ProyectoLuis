import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

/// Tabla cruda leída de un archivo: encabezados + filas de texto plano.
/// El asistente de importación decide después qué significa cada columna.
class RawTable {
  const RawTable({required this.headers, required this.rows});

  final List<String> headers;

  /// Cada fila tiene exactamente `headers.length` celdas (texto, ya limpio).
  final List<List<String>> rows;

  bool get isEmpty => headers.isEmpty || rows.isEmpty;
}

/// Lector agnóstico de tablas: soporta `.xlsx` (Excel moderno) y `.csv`
/// (con detección automática de separador `,`/`;`, BOM y saltos Windows).
/// El formato `.xls` antiguo no es soportado: se pide reexportar.
class TableFileReader {
  const TableFileReader();

  RawTable read({required String fileName, required Uint8List bytes}) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
      return _readCsv(bytes);
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.xlsm')) {
      return _readXlsx(bytes);
    }
    throw const FormatException(
        'Formato no soportado. En Excel usa "Guardar como" → .xlsx o .csv');
  }

  // ------------------------------------------------------------------ CSV

  RawTable _readCsv(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1); // BOM de Excel
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final firstLine = text.split('\n').first;
    // Excel en español suele exportar con ';'.
    final delimiter = ';'.allMatches(firstLine).length >
            ','.allMatches(firstLine).length
        ? ';'
        : ',';

    final parsed = CsvToListConverter(
      fieldDelimiter: delimiter,
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(text);

    return _build([
      for (final row in parsed)
        [for (final cell in row) cell.toString().trim()],
    ]);
  }

  // ----------------------------------------------------------------- XLSX

  RawTable _readXlsx(Uint8List bytes) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } on Exception {
      throw const FormatException(
          'No se pudo leer el archivo de Excel (¿está dañado o es .xls antiguo?).');
    }

    for (final sheet in excel.tables.values) {
      if (sheet.rows.isEmpty) continue;
      final all = [
        for (final row in sheet.rows)
          [for (final cell in row) _cellText(cell)],
      ];
      final table = _build(all);
      if (!table.isEmpty) return table;
    }
    throw const FormatException('El archivo no tiene hojas con datos.');
  }

  String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    // "24.0" se vuelve "24": stocks y cantidades enteras legibles.
    if (value is DoubleCellValue && value.value % 1 == 0) {
      return value.value.toInt().toString();
    }
    return value.toString().trim();
  }

  // ---------------------------------------------------------------- común

  RawTable _build(List<List<String>> all) {
    bool isEmptyRow(List<String> row) =>
        row.every((cell) => cell.trim().isEmpty);

    final nonEmpty = [
      for (final row in all)
        if (!isEmptyRow(row)) row,
    ];
    if (nonEmpty.isEmpty) return const RawTable(headers: [], rows: []);

    final rawHeaders = nonEmpty.first;
    final headers = [
      for (final (i, h) in rawHeaders.indexed)
        h.trim().isEmpty ? 'Columna ${i + 1}' : h.trim(),
    ];

    final rows = <List<String>>[];
    for (final row in nonEmpty.skip(1)) {
      // Normaliza el ancho de cada fila al de los encabezados.
      rows.add([
        for (var i = 0; i < headers.length; i++)
          i < row.length ? row[i].trim() : '',
      ]);
    }

    return RawTable(headers: headers, rows: rows);
  }
}
