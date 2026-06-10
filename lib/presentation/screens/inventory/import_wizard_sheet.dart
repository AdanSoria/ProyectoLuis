import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../data/import/table_file_reader.dart';
import '../../../domain/usecases/import_catalog_usecase.dart';
import '../../../domain/usecases/import_customers_usecase.dart';
import '../../providers.dart';

/// **Asistente de importación en 3 pasos** (Excel `.xlsx` o `.csv`):
///
///   Paso 1 · Archivo  → elegir destino (catálogo/clientes) y archivo
///   Paso 2 · Mapeo    → indicar qué columna corresponde a cada campo
///                        (con detección automática por nombre de encabezado)
///   Paso 3 · Importar → resumen, ejecución y reporte de resultados
///
/// Al no asumir ningún formato fijo, funciona con cualquier hoja que
/// tenga encabezados — exactamente lo necesario cuando aún no conocemos
/// el Excel de origen.
Future<void> showImportWizardSheet(BuildContext context) {
  final wide = MediaQuery.of(context).size.width >= 700;

  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => const Dialog(
        child: SizedBox(width: 560, height: 660, child: _ImportWizard()),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.95,
      child: _ImportWizard(),
    ),
  );
}

enum _ImportTarget {
  catalogo('Catálogo'),
  clientes('Clientes');

  const _ImportTarget(this.label);
  final String label;
}

/// Campo destino y las palabras clave para auto-detectar su columna.
class _FieldDef {
  const _FieldDef(this.key, this.label, this.required, this.keywords);

  final String key;
  final String label;
  final bool required;
  final List<String> keywords;
}

const _catalogFields = [
  _FieldDef('nombre', 'Nombre', true,
      ['nombre', 'producto', 'articulo', 'descripcion', 'item', 'concepto']),
  _FieldDef('precio_venta', 'Precio venta', true,
      ['precio venta', 'precio_venta', 'venta', 'publico', 'pv']),
  _FieldDef('precio_costo', 'Precio costo', false,
      ['precio costo', 'precio_costo', 'costo', 'compra', 'proveedor']),
  _FieldDef('categoria', 'Categoría', false,
      ['categoria', 'familia', 'linea', 'grupo', 'departamento']),
  _FieldDef('stock', 'Stock', false,
      ['stock', 'existencia', 'inventario', 'cantidad', 'disponible']),
  _FieldDef('unidad', 'Unidad', false,
      ['unidad', 'medida', 'presentacion', 'um']),
  _FieldDef('tipo', 'Tipo (producto/servicio)', false, ['tipo', 'clase']),
];

const _customerFields = [
  _FieldDef('nombre', 'Nombre', true,
      ['nombre', 'cliente', 'razon social', 'contacto']),
  _FieldDef('telefono', 'Teléfono', false,
      ['telefono', 'celular', 'whatsapp', 'tel', 'movil']),
  _FieldDef('notas', 'Notas / dirección', false,
      ['nota', 'observa', 'direccion', 'domicilio', 'comentario']),
];

class _ImportWizard extends ConsumerStatefulWidget {
  const _ImportWizard();

  @override
  ConsumerState<_ImportWizard> createState() => _ImportWizardState();
}

class _ImportWizardState extends ConsumerState<_ImportWizard> {
  int _step = 0;
  _ImportTarget _target = _ImportTarget.catalogo;
  RawTable? _table;
  String _fileName = '';
  final Map<String, int?> _mapping = {};
  bool _importing = false;
  ImportReport? _report;

  static const _titles = ['Archivo', 'Mapeo de columnas', 'Importar'];

  List<_FieldDef> get _fields =>
      _target == _ImportTarget.catalogo ? _catalogFields : _customerFields;

  bool get _requiredMapped =>
      _fields.where((f) => f.required).every((f) => _mapping[f.key] != null);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                if (_step > 0 && _report == null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed:
                        _importing ? null : () => setState(() => _step -= 1),
                  ),
                Expanded(
                  child: Text(
                    'Paso ${_step + 1} de 3 · ${_titles[_step]}',
                    style: textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed:
                      _importing ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: i <= _step
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  if (i < 2) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
          Expanded(
            child: switch (_step) {
              0 => _buildFileStep(),
              1 => _buildMappingStep(),
              _ => _buildImportStep(),
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ paso 1: archivo

  Widget _buildFileStep() {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('¿Qué quieres importar?', style: textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<_ImportTarget>(
          segments: [
            for (final target in _ImportTarget.values)
              ButtonSegment(
                value: target,
                icon: Icon(target == _ImportTarget.catalogo
                    ? Icons.inventory_2_outlined
                    : Icons.people_outline),
                label: Text(target.label),
              ),
          ],
          selected: {_target},
          onSelectionChanged: (selection) => setState(() {
            _target = selection.first;
            _mapping.clear();
            if (_table != null) _autoMap();
          }),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 22)),
          onPressed: _pickFile,
          icon: const Icon(Icons.folder_open),
          label: Text(_table == null
              ? 'Elegir archivo  (.xlsx / .csv)'
              : 'Cambiar archivo'),
        ),
        if (_table != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.table_chart_outlined, color: scheme.primary),
              title: Text(_fileName),
              subtitle: Text(
                  '${_table!.rows.length} filas · ${_table!.headers.length} columnas detectadas'),
              trailing: FilledButton(
                onPressed: () => setState(() => _step = 1),
                child: const Text('CONTINUAR'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Tip: si tu archivo es .xls (Excel antiguo), ábrelo y usa '
          'Archivo → Guardar como → .xlsx o .csv. La primera fila debe '
          'tener los títulos de las columnas.',
          style: textTheme.bodySmall?.copyWith(color: scheme.outline),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Elegir archivo a importar',
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xlsm', 'csv', 'txt'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    try {
      final table =
          const TableFileReader().read(fileName: file.name, bytes: bytes);
      if (table.isEmpty) {
        throw const FormatException(
            'El archivo no tiene filas de datos debajo del encabezado.');
      }
      if (!mounted) return;
      setState(() {
        _table = table;
        _fileName = file.name;
        _mapping.clear();
        _autoMap();
        _step = 1;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  /// Detección automática: asigna a cada campo la primera columna libre
  /// cuyo encabezado contenga alguna de sus palabras clave.
  void _autoMap() {
    final headers = [for (final h in _table!.headers) _normalizeHeader(h)];
    final used = <int>{};

    int? findColumn(List<String> keywords) {
      for (final keyword in keywords) {
        for (var i = 0; i < headers.length; i++) {
          if (!used.contains(i) && headers[i].contains(keyword)) return i;
        }
      }
      return null;
    }

    for (final field in _fields) {
      final index = findColumn(field.keywords);
      if (index != null) {
        _mapping[field.key] = index;
        used.add(index);
      }
    }

    // 'precio' a secas cuenta como precio de venta si quedó libre.
    if (_target == _ImportTarget.catalogo &&
        _mapping['precio_venta'] == null) {
      final index = findColumn(const ['precio']);
      if (index != null) _mapping['precio_venta'] = index;
    }
  }

  String _normalizeHeader(String value) {
    var v = value.trim().toLowerCase();
    const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    accents.forEach((from, to) => v = v.replaceAll(from, to));
    return v;
  }

  // -------------------------------------------------------- paso 2: mapeo

  Widget _buildMappingStep() {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final table = _table!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '$_fileName · ${table.rows.length} filas. Indica qué columna '
          'corresponde a cada campo:',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        for (final field in _fields)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    field.required ? '${field.label} *' : field.label,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          field.required ? FontWeight.bold : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int?>(
                    isExpanded: true,
                    value: _mapping[field.key],
                    hint: const Text('— No importar —'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('— No importar —'),
                      ),
                      for (final (i, header) in table.headers.indexed)
                        DropdownMenuItem<int?>(
                          value: i,
                          child: Text(header,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _mapping[field.key] = value),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text('Vista previa', style: textTheme.labelLarge),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in table.rows.take(3))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _previewLine(row),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed:
              _requiredMapped ? () => setState(() => _step = 2) : null,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('CONTINUAR'),
        ),
        if (!_requiredMapped)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Faltan campos obligatorios (*) por mapear.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
      ],
    );
  }

  String _cell(List<String> row, String key) {
    final index = _mapping[key];
    if (index == null || index >= row.length) return '';
    return row[index];
  }

  String _previewLine(List<String> row) {
    if (_target == _ImportTarget.catalogo) {
      final name = _cell(row, 'nombre');
      final sale = Money.fromText(_cell(row, 'precio_venta'));
      final parts = [
        name.isEmpty ? '(sin nombre)' : name,
        'venta ${Money.format(sale)}',
        if (_mapping['precio_costo'] != null)
          'costo ${Money.format(Money.fromText(_cell(row, 'precio_costo')))}',
        if (_mapping['stock'] != null) 'stock ${_cell(row, 'stock')}',
      ];
      return parts.join(' · ');
    }
    final name = _cell(row, 'nombre');
    final phone = _cell(row, 'telefono');
    return [
      name.isEmpty ? '(sin nombre)' : name,
      if (phone.isNotEmpty) phone,
    ].join(' · ');
  }

  // ----------------------------------------------------- paso 3: importar

  Widget _buildImportStep() {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final report = _report;

    if (report != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(
            report.hasErrors ? Icons.warning_amber : Icons.check_circle,
            size: 48,
            color: report.hasErrors ? scheme.tertiary : scheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            'Importación terminada',
            textAlign: TextAlign.center,
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            '${report.created} nuevos · ${report.updated} actualizados · '
            '${report.skipped.length} omitidos',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          ),
          if (report.skipped.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final skip in report.skipped.take(8))
                      Text('Fila ${skip.rowNumber}: ${skip.reason}',
                          style: textTheme.bodySmall),
                    if (report.skipped.length > 8)
                      Text('… y ${report.skipped.length - 8} más',
                          style: textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CERRAR'),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se procesarán ${_table!.rows.length} filas de '
                  '"$_fileName" hacia ${_target.label}.',
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _target == _ImportTarget.catalogo
                      ? 'Los artículos cuyo nombre ya exista se ACTUALIZAN '
                          '(precios, stock, categoría); los demás se crean '
                          'nuevos. Nada se borra.'
                      : 'Los clientes se deduplican por teléfono o nombre; '
                          'nada se borra.',
                  style: textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _importing ? null : _runImport,
          icon: _importing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file),
          label: const Text('IMPORTAR AHORA'),
        ),
      ],
    );
  }

  Future<void> _runImport() async {
    setState(() => _importing = true);

    final rows = _table!.rows;
    final ImportReport report;

    if (_target == _ImportTarget.catalogo) {
      report = await ref.read(importCatalogUseCaseProvider).call([
        for (final (index, row) in rows.indexed)
          CatalogRowInput(
            // +2: las filas del archivo empiezan en 1 y la 1 es encabezado.
            rowNumber: index + 2,
            name: _cell(row, 'nombre'),
            salePriceCents: Money.fromText(_cell(row, 'precio_venta')),
            costPriceCents: _mapping['precio_costo'] == null
                ? null
                : Money.fromText(_cell(row, 'precio_costo')),
            stock: _mapping['stock'] == null
                ? null
                : _parseQuantity(_cell(row, 'stock')),
            category: _cell(row, 'categoria'),
            unit: _cell(row, 'unidad'),
            isService:
                _cell(row, 'tipo').toLowerCase().contains('serv'),
          ),
      ]);
    } else {
      report = await ref.read(importCustomersUseCaseProvider).call([
        for (final (index, row) in rows.indexed)
          CustomerRowInput(
            rowNumber: index + 2,
            name: _cell(row, 'nombre'),
            phone: _cell(row, 'telefono'),
            notes: _cell(row, 'notas'),
          ),
      ]);
    }

    if (!mounted) return;
    refreshAfterMutation(ref);
    setState(() {
      _importing = false;
      _report = report;
    });
  }

  double _parseQuantity(String value) =>
      double.tryParse(value.replaceAll(',', '').trim()) ?? 0;
}
