import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/catalog_item.dart';
import '../../../domain/entities/product_variant.dart';
import '../../providers.dart';

/// Diálogo de **desensamble (bulk breaking)**: convierte presentaciones
/// mayores en menores con vista previa de la conversión.
/// Ej.: 1 "Costal 40 kg" → 40 de "Granel kg".
Future<void> showBreakVariantDialog(
  BuildContext context, {
  required Product product,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: SizedBox(width: 440, child: _BreakVariantContent(product)),
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
  ProductVariant? _source;
  ProductVariant? _target;
  double _quantity = 1;
  bool _busy = false;

  List<ProductVariant> get _variants => widget.product.sellableVariants;

  @override
  void initState() {
    super.initState();
    // Preselección sensata: la de mayor contenido hacia la de menor.
    final sorted = [..._variants]
      ..sort((a, b) => b.contentUnits.compareTo(a.contentUnits));
    if (sorted.length >= 2) {
      _source = sorted.first;
      _target = sorted.last;
    }
  }

  double? get _credited {
    final source = _source;
    final target = _target;
    if (source == null || target == null) return null;
    if (source.contentUnits <= 0 || target.contentUnits <= 0) return null;
    return _quantity * source.contentUnits / target.contentUnits;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final credited = _credited;

    String fmt(double v) =>
        v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Fraccionar ${widget.product.name}',
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
                      '${variant.name} · ${fmt(variant.stock)} disponibles'),
                  selected: _source?.id == variant.id,
                  onSelected: (_) => setState(() => _source = variant),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Hacia (destino)', style: textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final variant in _variants)
                ChoiceChip(
                  label: Text(variant.name),
                  selected: _target?.id == variant.id,
                  onSelected: (_) => setState(() => _target = variant),
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
              Text(fmt(_quantity), style: textTheme.titleMedium),
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
                  '${fmt(_quantity)} × ${_source!.name}  →  '
                  '${fmt(credited)} × ${_target!.name}',
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
            label: const Text('FRACCIONAR'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _break() async {
    setState(() => _busy = true);

    final result = await ref.read(breakVariantUseCaseProvider).call(
          productId: widget.product.id,
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
            'Listo: +${credited % 1 == 0 ? credited.toInt() : credited.toStringAsFixed(2)} '
            '${_target!.name} en inventario.',
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
