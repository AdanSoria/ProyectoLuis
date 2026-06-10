import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/export/excel_exporter.dart';
import '../../providers.dart';

/// Exporta el historial a Excel en 2 toques: rango + EXPORTAR.
Future<void> showExportDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      child: SizedBox(width: 430, child: _ExportContent()),
    ),
  );
}

enum _ExportRange {
  hoy('Hoy'),
  semana('7 días'),
  mes('Mes actual'),
  todo('Todo');

  const _ExportRange(this.label);
  final String label;
}

class _ExportContent extends ConsumerStatefulWidget {
  const _ExportContent();

  @override
  ConsumerState<_ExportContent> createState() => _ExportContentState();
}

class _ExportContentState extends ConsumerState<_ExportContent> {
  _ExportRange _range = _ExportRange.mes;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Exportar a Excel', style: textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Genera un .xlsx con las hojas Ventas, Detalle por artículo '
            'e Inventario valorizado.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          SegmentedButton<_ExportRange>(
            segments: [
              for (final range in _ExportRange.values)
                ButtonSegment(value: range, label: Text(range.label)),
            ],
            selected: {_range},
            onSelectionChanged: (selection) =>
                setState(() => _range = selection.first),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_view),
            label: const Text('EXPORTAR'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  (DateTime, DateTime) _dates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 1));
    return switch (_range) {
      _ExportRange.hoy => (today, end),
      _ExportRange.semana => (today.subtract(const Duration(days: 6)), end),
      _ExportRange.mes => (DateTime(now.year, now.month), end),
      _ExportRange.todo => (DateTime(2000), end),
    };
  }

  Future<void> _export() async {
    setState(() => _busy = true);

    try {
      final (from, to) = _dates();
      final transactions = await ref
          .read(transactionRepositoryProvider)
          .getByDateRange(from, to);
      final catalog = await ref
          .read(catalogRepositoryProvider)
          .getAll(includeInactive: true);

      final bytes = const ExcelExporter()
          .buildReport(transactions: transactions, catalog: catalog);

      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final fileName =
          'agropos_${_range.name}_${now.year}-${two(now.month)}-${two(now.day)}.xlsx';

      // En escritorio el diálogo solo devuelve la ruta y nosotros
      // escribimos; en Android/iOS el plugin guarda los bytes él mismo.
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar reporte',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );

      if (!mounted) return;
      if (path == null) {
        setState(() => _busy = false); // canceló el diálogo de guardado
        return;
      }

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await File(path).writeAsBytes(bytes, flush: true);
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Reporte guardado: $path '
            '(${transactions.length} transacciones)'),
      ));
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo exportar: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }
}
