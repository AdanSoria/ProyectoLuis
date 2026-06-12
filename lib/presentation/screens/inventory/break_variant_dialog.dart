import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../domain/entities/catalog_item.dart';
import '../../../domain/entities/product_variant.dart';
import '../../providers.dart';

/// Diálogo **Pasar a granel** (desensamble): convierte presentaciones
/// mayores en menores con vista previa de la conversión.
/// Ej.: 2 "Costal 40 kg" → 80 de "Granel kg".
///
/// Si el producto aún no tiene presentación a granel, se puede CREAR
/// aquí mismo: lo abierto queda como apartado propio, con su stock y
/// su precio de menudeo independientes.
Future<void> showBreakVariantDialog(
  BuildContext context, {
  required Product product,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: SizedBox(width: 460, child: _BreakVariantContent(product)),
    ),
  );
}

class _BreakVariantContent extends ConsumerStatefulWidget {
  const _BreakVariantContent(this.product);

  final Product product;

  @override
  ConsumerState<_BreakVariantContent> createState() =>
      _BreakVariantContentState();
}

class _BreakVariantContentState extends ConsumerState<_BreakVariantContent> {
  late Product _product = widget.product;
  ProductVariant? _source;
  ProductVariant? _target;
  double _quantity = 1;
  bool _busy = false;

  List<ProductVariant> get _variants => _product.sellableVariants;

  @override
  void initState() {
    super.initState();
    // Preselección sensata: la de mayor contenido hacia la de menor.
    final sorted = [..._variants]
      ..sort((a, b) => b.contentUnits.compareTo(a.contentUnits));
    if (sorted.length >= 2) {
      _source = sorted.first;
      _target = sorted.last;
    } else if (sorted.isNotEmpty) {
      _source = sorted.first;
    }
  }

  double? get _credited {
    final source = _source;
    final target = _target;
    if (source == null || target == null) return null;
    if (source.contentUnits <= 0 || target.contentUnits <= 0) return null;
    return _quantity * source.contentUnits / target.contentUnits;
  }

  String _fmt(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final credited = _credited;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pasar a granel · ${_product.name}',
                style: textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Abrir (origen)', style: textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final variant in _variants)
                  ChoiceChip(
                    label: Text(
                        '${variant.name} · ${_fmt(variant.stock)} disponibles'),
                    selected: _source?.id == variant.id,
                    onSelected: (_) => setState(() => _source = variant),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Hacia (granel / destino)', style: textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final variant in _variants)
                  if (variant.id != _source?.id)
                    ChoiceChip(
                      label: Text(variant.name),
                      selected: _target?.id == variant.id,
                      onSelected: (_) => setState(() => _target = variant),
                    ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Crear presentación granel'),
                  onPressed: _busy ? null : _createBulkVariant,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Cantidad a abrir', style: textTheme.bodyMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _quantity <= 1
                      ? null
                      : () => setState(() => _quantity -= 1),
                ),
                // Tocar el número permite capturar fracciones (½ costal).
                InkWell(
                  onTap: _askQuantity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child:
                        Text(_fmt(_quantity), style: textTheme.titleMedium),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _quantity += 1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (credited != null && _source != null && _target != null)
              Card(
                color: scheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${_fmt(_quantity)} × ${_source!.name}  →  '
                    '${_fmt(credited)} × ${_target!.name}',
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || _source == null || _target == null
                  ? null
                  : _break,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.call_split),
              label: const Text('CONVERTIR A GRANEL'),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _askQuantity() async {
    final controller = TextEditingController(text: _fmt(_quantity));
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cantidad a abrir'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration:
              const InputDecoration(hintText: 'Acepta fracciones: 0.5'),
          onSubmitted: (v) =>
              Navigator.of(dialogContext).pop(double.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(double.tryParse(controller.text)),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (value != null && value > 0) setState(() => _quantity = value);
  }

  /// Crea la presentación a granel del producto sin salir del flujo:
  /// queda como apartado propio (stock y precio de menudeo separados).
  Future<void> _createBulkVariant() async {
    final source = _source ?? _variants.first;
    // Sugerencias proporcionales a partir del origen; el menudeo suele
    // venderse un poco más caro, pero eso lo decide el usuario.
    final suggestedSale = source.contentUnits > 0
        ? (source.salePriceCents / source.contentUnits).ceil()
        : source.salePriceCents;
    final suggestedCost = source.contentUnits > 0
        ? (source.costPriceCents / source.contentUnits).ceil()
        : source.costPriceCents;

    final priceController =
        TextEditingController(text: (suggestedSale / 100).toStringAsFixed(2));
    var unit = 'kg';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Nueva presentación granel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                children: [
                  for (final u in const ['kg', 'litro', 'pieza'])
                    ChoiceChip(
                      label: Text(u),
                      selected: unit == u,
                      onSelected: (_) => setLocal(() => unit = u),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Precio de venta por $unit',
                  prefixText: r'$ ',
                  helperText: 'Sugerido proporcional; ajusta tu menudeo',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final sale = Money.fromText(priceController.text);
    if (sale <= 0) return;

    final variant = ProductVariant(
      id: ref.read(idGeneratorProvider).newId(),
      productId: _product.id,
      name: 'Granel $unit',
      costPriceCents: suggestedCost,
      salePriceCents: sale,
      stock: 0,
      unit: unit,
      contentUnits: 1,
    );

    final updated = _product.copyWith(
      variants: [..._product.variants, variant],
      updatedAt: DateTime.now().toUtc(),
    );
    final saved =
        await ref.read(catalogRepositoryProvider).save(updated, isNew: false);

    if (!mounted) return;
    final failure = saved.failureOrNull;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failure.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    refreshAfterMutation(ref);
    // Recargar el producto fresco y dejar el granel como destino.
    final fresh =
        await ref.read(catalogRepositoryProvider).getById(_product.id);
    if (!mounted || fresh is! Product) return;
    setState(() {
      _product = fresh;
      _target =
          _product.variants.where((v) => v.id == variant.id).firstOrNull;
    });
  }

  Future<void> _break() async {
    setState(() => _busy = true);

    final result = await ref.read(breakVariantUseCaseProvider).call(
          productId: _product.id,
          sourceVariantId: _source!.id,
          targetVariantId: _target!.id,
          quantity: _quantity,
        );

    if (!mounted) return;

    result.fold(
      ok: (credited) {
        refreshAfterMutation(ref);
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Listo: +${_fmt(credited)} ${_target!.name} en inventario.',
          ),
        ));
      },
      err: (failure) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      },
    );
  }
}
