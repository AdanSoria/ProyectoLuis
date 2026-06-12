import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../domain/entities/catalog_item.dart';
import '../../../domain/entities/product_variant.dart';
import '../../providers.dart';

/// Gestión de presentaciones (SKUs) de un producto: agregar, editar,
/// definir contenido (para A GRANEL) y precios escalonados por volumen.
/// Cada cambio se guarda de inmediato (atómico + Outbox).
Future<void> showVariantManagerSheet(
  BuildContext context, {
  required String productId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: SizedBox(
        width: 520,
        height: 560,
        child: _VariantManager(productId: productId),
      ),
    ),
  );
}

class _VariantManager extends ConsumerStatefulWidget {
  const _VariantManager({required this.productId});

  final String productId;

  @override
  ConsumerState<_VariantManager> createState() => _VariantManagerState();
}

class _VariantManagerState extends ConsumerState<_VariantManager> {
  Product? _product;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final item =
        await ref.read(catalogRepositoryProvider).getById(widget.productId);
    if (!mounted) return;
    setState(() {
      _product = item is Product ? item : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final product = _product;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : product == null
              ? const Center(child: Text('El producto ya no existe.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Presentaciones · ${product.name}',
                              style: textTheme.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final variant in product.variants)
                            ListTile(
                              dense: true,
                              onTap: () => _editVariant(product, variant),
                              title: Row(
                                children: [
                                  Expanded(child: Text(variant.name)),
                                  if (variant.isDefault)
                                    const Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text('default'),
                                    ),
                                  if (!variant.active)
                                    const Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text('oculta'),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                'Venta ${Money.format(variant.salePriceCents)} · '
                                'Costo ${Money.format(variant.costPriceCents)} · '
                                'Stock ${variant.stock % 1 == 0 ? variant.stock.toInt() : variant.stock} ${variant.unit} · '
                                'Contiene ${variant.contentUnits % 1 == 0 ? variant.contentUnits.toInt() : variant.contentUnits}'
                                '${variant.priceTiers.isEmpty ? '' : ' · ${variant.priceTiers.length} escalón(es)'}',
                              ),
                              trailing:
                                  const Icon(Icons.edit_outlined, size: 18),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _editVariant(product, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar presentación'),
                    ),
                  ],
                ),
    );
  }

  Future<void> _editVariant(Product product, ProductVariant? variant) async {
    final result = await showDialog<ProductVariant>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 440,
          child: _VariantForm(product: product, existing: variant),
        ),
      ),
    );
    if (result == null || !mounted) return;

    final variants = [...product.variants];
    final index = variants.indexWhere((v) => v.id == result.id);
    if (index >= 0) {
      variants[index] = result;
    } else {
      variants.add(result);
    }

    final updated = product.copyWith(
      variants: variants,
      updatedAt: DateTime.now().toUtc(),
      // El espejo del catálogo refleja a la default.
      costPriceCents: variants.first.costPriceCents,
      salePriceCents: variants.first.salePriceCents,
      stock: variants.first.stock,
      unit: variants.first.unit,
    );

    final saved =
        await ref.read(catalogRepositoryProvider).save(updated, isNew: false);

    if (!mounted) return;
    final message = saved.failureOrNull?.message;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }
    refreshAfterMutation(ref);
    await _reload();
  }
}

class _VariantForm extends ConsumerStatefulWidget {
  const _VariantForm({required this.product, this.existing});

  final Product product;
  final ProductVariant? existing;

  @override
  ConsumerState<_VariantForm> createState() => _VariantFormState();
}

class _VariantFormState extends ConsumerState<_VariantForm> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _cost;
  late final TextEditingController _sale;
  late final TextEditingController _stock;
  late final TextEditingController _content;
  late List<({TextEditingController min, TextEditingController price})> _tiers;
  late bool _active;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    _name = TextEditingController(text: v?.name ?? '');
    _sku = TextEditingController(text: v?.sku ?? '');
    _cost = TextEditingController(
        text: v == null ? '' : (v.costPriceCents / 100).toStringAsFixed(2));
    _sale = TextEditingController(
        text: v == null ? '' : (v.salePriceCents / 100).toStringAsFixed(2));
    _stock = TextEditingController(
        text: v == null
            ? '0'
            : (v.stock % 1 == 0
                ? v.stock.toInt().toString()
                : v.stock.toString()));
    _content = TextEditingController(
        text: v == null
            ? '1'
            : (v.contentUnits % 1 == 0
                ? v.contentUnits.toInt().toString()
                : v.contentUnits.toString()));
    _tiers = [
      for (final tier in v?.priceTiers ?? const <PriceTier>[])
        (
          min: TextEditingController(
              text: tier.minQuantity % 1 == 0
                  ? tier.minQuantity.toInt().toString()
                  : tier.minQuantity.toString()),
          price: TextEditingController(
              text: (tier.unitPriceCents / 100).toStringAsFixed(2)),
        ),
    ];
    _active = v?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _cost.dispose();
    _sale.dispose();
    _stock.dispose();
    _content.dispose();
    for (final tier in _tiers) {
      tier.min.dispose();
      tier.price.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isDefault = widget.existing?.isDefault ?? false;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isNew ? 'Nueva presentación' : 'Editar presentación',
                style: textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Costal 50 kg, Granel kg…',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sku,
                    decoration:
                        const InputDecoration(labelText: 'SKU (opcional)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _content,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Contiene',
                      helperText: 'unidades base (p/ A GRANEL)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cost,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Precio costo', prefixText: r'$ '),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sale,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Precio venta', prefixText: r'$ '),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (_isNew) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _stock,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Stock inicial',
                  helperText: 'Después se ajusta desde el inventario',
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Precios por volumen', style: textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _tiers.add((
                        min: TextEditingController(),
                        price: TextEditingController(),
                      ))),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Escalón'),
                ),
              ],
            ),
            if (_tiers.isEmpty)
              Text(
                'Sin escalones: siempre aplica el precio de venta.',
                style: textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            for (final (index, tier) in _tiers.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tier.min,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Desde (cantidad)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: tier.price,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Precio unitario', prefixText: r'$ '),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _tiers.removeAt(index)),
                    ),
                  ],
                ),
              ),
            if (!_isNew && !isDefault) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Visible en el mostrador'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  _name.text.trim().isEmpty || Money.fromText(_sale.text) <= 0
                      ? null
                      : _submit,
              icon: const Icon(Icons.save_outlined),
              label: const Text('GUARDAR'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final existing = widget.existing;
    final tiers = <PriceTier>[
      for (final tier in _tiers)
        if ((double.tryParse(tier.min.text.replaceAll(',', '')) ?? 0) > 0 &&
            Money.fromText(tier.price.text) > 0)
          PriceTier(
            minQuantity: double.parse(tier.min.text.replaceAll(',', '')),
            unitPriceCents: Money.fromText(tier.price.text),
          ),
    ];

    final variant = ProductVariant(
      id: existing?.id ?? ref.read(idGeneratorProvider).newId(),
      productId: widget.product.id,
      name: _name.text.trim(),
      sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      costPriceCents: Money.fromText(_cost.text),
      salePriceCents: Money.fromText(_sale.text),
      stock: existing?.stock ??
          (double.tryParse(_stock.text.replaceAll(',', '')) ?? 0),
      unit: existing?.unit ?? widget.product.unit,
      contentUnits: double.tryParse(_content.text.replaceAll(',', '')) ?? 1,
      isDefault: existing?.isDefault ?? false,
      active: _active,
      priceTiers: tiers,
    );

    Navigator.of(context).pop(variant);
  }
}
