import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../domain/entities/catalog_item.dart';
import '../../../domain/entities/product_variant.dart';
import '../../providers.dart';
import 'variant_manager_sheet.dart';

/// Alta/edición exprés de artículos. Hoja compacta, sin Form tradicional:
/// el botón Guardar se habilita en cuanto hay nombre y precio de venta.
Future<void> showItemEditorSheet(BuildContext context, {CatalogItem? existing}) {
  final wide = MediaQuery.of(context).size.width >= 700;

  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(width: 460, child: _ItemEditor(existing: existing)),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ItemEditor(existing: existing),
    ),
  );
}

class _ItemEditor extends ConsumerStatefulWidget {
  const _ItemEditor({this.existing});

  final CatalogItem? existing;

  @override
  ConsumerState<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends ConsumerState<_ItemEditor> {
  late bool _isService;
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _cost;
  late final TextEditingController _sale;
  late final TextEditingController _stock;
  late String _unit;
  bool _saving = false;

  static const _units = ['pieza', 'bulto', 'kg', 'litro', 'frasco', 'rollo'];

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _isService = existing?.isService ?? false;
    _name = TextEditingController(text: existing?.name ?? '');
    _category = TextEditingController(text: existing?.category ?? '');
    _cost = TextEditingController(
        text: existing == null
            ? ''
            : (existing.costPriceCents / 100).toStringAsFixed(2));
    _sale = TextEditingController(
        text: existing == null
            ? ''
            : (existing.salePriceCents / 100).toStringAsFixed(2));
    _stock = TextEditingController();
    _unit = existing?.unit ?? 'pieza';
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _cost.dispose();
    _sale.dispose();
    _stock.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving &&
      _name.text.trim().isNotEmpty &&
      Money.fromText(_sale.text) > 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final categories = ref
        .watch(categoriesProvider)
        .maybeWhen(data: (c) => c, orElse: () => const <String>[]);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isNew ? 'Nuevo artículo' : 'Editar artículo',
                style: textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.inventory_2_outlined),
                  label: Text('Producto'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.support_agent),
                  label: Text('Servicio'),
                ),
              ],
              selected: {_isService},
              onSelectionChanged: _isNew
                  ? (selection) =>
                      setState(() => _isService = selection.first)
                  : null,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Categoría'),
              onChanged: (_) => setState(() {}),
            ),
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in categories)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(category),
                      onPressed: () =>
                          setState(() => _category.text = category),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Precio costo',
                      prefixText: r'$ ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sale,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Precio venta',
                      prefixText: r'$ ',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (!_isService) ...[
              const SizedBox(height: 12),
              if (_isNew)
                TextField(
                  controller: _stock,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Stock inicial',
                    helperText:
                        'Después se ajusta con +/- desde el inventario',
                  ),
                )
              else if (widget.existing is Product)
                OutlinedButton.icon(
                  onPressed: () => showVariantManagerSheet(
                    context,
                    productId: widget.existing!.id,
                  ),
                  icon: const Icon(Icons.category_outlined),
                  label: Text(
                    'Presentaciones '
                    '(${(widget.existing! as Product).sellableVariants.length})'
                    ' · fraccionar y volumen',
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final unit in _units)
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(unit),
                      selected: _unit == unit,
                      onSelected: (_) => setState(() => _unit = unit),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _canSave ? _save : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(_isNew ? 'GUARDAR' : 'GUARDAR CAMBIOS'),
            ),
            if (!_isNew)
              TextButton.icon(
                onPressed: _saving ? null : _deactivate,
                icon: const Icon(Icons.visibility_off_outlined, size: 18),
                label: const Text('Ocultar del catálogo'),
              ),
            TextButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final now = DateTime.now().toUtc();
    final existing = widget.existing;
    final id = existing?.id ?? ref.read(idGeneratorProvider).newId();
    final name = _name.text.trim();
    final category =
        _category.text.trim().isEmpty ? 'General' : _category.text.trim();
    final cost = Money.fromText(_cost.text);
    final sale = Money.fromText(_sale.text);

    final CatalogItem item;
    if (_isService) {
      item = Service(
        id: id,
        name: name,
        category: category,
        costPriceCents: cost,
        salePriceCents: sale,
        active: existing?.active ?? true,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
    } else if (existing is Product) {
      // Los campos base editan a la variante DEFAULT; las demás
      // presentaciones se conservan tal cual.
      final defaultVariant = existing.defaultVariant.copyWith(
        costPriceCents: cost,
        salePriceCents: sale,
        unit: _unit,
      );
      final others = existing.variants.length > 1
          ? existing.variants.sublist(1)
          : const <ProductVariant>[];
      item = existing.copyWith(
        name: name,
        category: category,
        costPriceCents: cost,
        salePriceCents: sale,
        unit: _unit,
        updatedAt: now,
        variants: [defaultVariant, ...others],
      );
    } else {
      item = Product.simple(
        id: id,
        name: name,
        category: category,
        costPriceCents: cost,
        salePriceCents: sale,
        unit: _unit,
        createdAt: now,
        updatedAt: now,
        stock: double.tryParse(_stock.text) ?? 0,
      );
    }

    final result =
        await ref.read(catalogRepositoryProvider).save(item, isNew: _isNew);

    if (!mounted) return;

    result.fold(
      ok: (saved) {
        refreshAfterMutation(ref);
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('"${saved.name}" guardado en el catálogo.')),
        );
      },
      err: (failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      },
    );
  }

  /// Borrado suave: el artículo deja de mostrarse pero su historia
  /// de ventas permanece intacta.
  Future<void> _deactivate() async {
    final existing = widget.existing!;
    setState(() => _saving = true);

    final now = DateTime.now().toUtc();
    final item = switch (existing) {
      final Product p => p.copyWith(active: false, updatedAt: now),
      final Service s => s.copyWith(active: false, updatedAt: now),
    };

    final result =
        await ref.read(catalogRepositoryProvider).save(item, isNew: false);

    if (!mounted) return;

    result.fold(
      ok: (_) {
        refreshAfterMutation(ref);
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('"${existing.name}" oculto del catálogo.')),
        );
      },
      err: (failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      },
    );
  }
}
