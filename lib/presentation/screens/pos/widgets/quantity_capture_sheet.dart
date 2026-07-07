import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/utils/money.dart';
import '../../../../domain/entities/catalog_item.dart';
import '../../../../domain/entities/product_variant.dart';
import '../../../providers.dart';
import '../../../widgets/numeric_keypad.dart';

/// **Hoja unificada de captura**: elige presentación (si hay varias) y
/// cantidad en un solo paso, con teclado numérico propio, atajos de
/// cantidad y precio/total recalculándose en vivo.
///
/// Reemplaza el antiguo flujo de dos modales (elegir variante → capturar
/// cantidad). Caso común = 2 toques: variante + un atajo de cantidad.
///
/// (Extensible a futuro a "cantidad primero, producto después" dockeando
/// el teclado permanente en el mostrador; hoy vive por producto.)
Future<void> showQuantityCaptureSheet(
  BuildContext context,
  WidgetRef ref, {
  required Product product,
  ProductVariant? initialVariant,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _QuantityCaptureSheet(
      product: product,
      initialVariant: initialVariant,
    ),
  );
}

class _QuantityCaptureSheet extends ConsumerStatefulWidget {
  const _QuantityCaptureSheet({required this.product, this.initialVariant});

  final Product product;
  final ProductVariant? initialVariant;

  @override
  ConsumerState<_QuantityCaptureSheet> createState() =>
      _QuantityCaptureSheetState();
}

class _QuantityCaptureSheetState extends ConsumerState<_QuantityCaptureSheet> {
  late ProductVariant _variant;
  String _qtyText = '';

  List<ProductVariant> get _variants => widget.product.sellableVariants;

  @override
  void initState() {
    super.initState();
    _variant = _resolveInitialVariant();
  }

  ProductVariant _resolveInitialVariant() {
    if (widget.initialVariant != null) return widget.initialVariant!;
    // Última variante usada para este producto en la sesión.
    final lastId =
        ref.read(lastVariantByProductProvider)[widget.product.id];
    if (lastId != null) {
      final match = _variants.where((v) => v.id == lastId).firstOrNull;
      if (match != null) return match;
    }
    return _variants.first;
  }

  double get _quantity => double.tryParse(_qtyText) ?? 0;

  /// Presentación mayor de referencia (para los atajos porcentuales de una
  /// variante unitaria de granel).
  ProductVariant? get _referenceForPercent {
    if (_variant.contentUnits != 1) return null;
    ProductVariant? ref;
    for (final v in _variants) {
      if (v.contentUnits > 1 &&
          (ref == null || v.contentUnits > ref.contentUnits)) {
        ref = v;
      }
    }
    return ref;
  }

  /// Chips de atajo: (etiqueta, cantidad a fijar).
  List<(String, double)> get _shortcuts {
    String fmt(double v) =>
        v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

    // 1) Variante mayor (costal): % de su propio contenido → fracción de
    //    la presentación (50% = medio costal), mostrando el equivalente.
    if (_variant.contentUnits > 1) {
      return [
        for (final pct in const [10, 25, 50, 100])
          (
            '$pct% · ${fmt(_variant.contentUnits * pct / 100)} ${_variant.unit == 'bulto' ? 'u' : _variant.unit}',
            pct / 100,
          ),
      ];
    }
    // 2) Granel con presentación mayor de referencia: % del costal en kg.
    final ref = _referenceForPercent;
    if (ref != null) {
      return [
        for (final pct in const [10, 25, 50, 100])
          (
            '$pct% · ${fmt(ref.contentUnits * pct / 100)} ${_variant.unit}',
            ref.contentUnits * pct / 100,
          ),
      ];
    }
    // 3) Granel suelto: cantidades comunes por unidad (AppConfig).
    if (AppConfig.isWeightVolume(_variant.unit)) {
      return [
        for (final q in AppConfig.bulkShortcutsFor(_variant.unit))
          ('${fmt(q)} ${_variant.unit}', q),
      ];
    }
    // 4) Unidad de pieza: enteros rápidos.
    return [for (final q in const <double>[1, 2, 3, 5, 10]) (fmt(q), q)];
  }

  int get _unitPriceCents => _variant.priceForQuantity(_quantity <= 0 ? 1 : _quantity);
  bool get _volumeDiscount => _unitPriceCents < _variant.salePriceCents;
  int get _totalCents => (_unitPriceCents * _quantity).round();

  void _confirm() {
    if (_quantity <= 0) return;
    ref.read(cartProvider.notifier).add(
          widget.product,
          variant: _variant,
          quantity: _quantity,
        );
    // Recordar la variante para la próxima vez (sesión).
    ref.read(lastVariantByProductProvider.notifier).update(
          (m) => {...m, widget.product.id: _variant.id},
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final multi = _variants.length > 1;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(widget.product.name, style: textTheme.titleLarge),
              const SizedBox(height: 8),
              if (multi)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in _variants)
                      ChoiceChip(
                        label: Text(
                            '${v.name} · ${Money.format(v.salePriceCents)}'),
                        selected: _variant.id == v.id,
                        onSelected: v.stock <= 0
                            ? null
                            : (_) => setState(() => _variant = v),
                      ),
                  ],
                ),
              if (multi) const SizedBox(height: 12),
              // -------- precio unitario + total en vivo --------
              Card(
                color: scheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Precio unitario', style: textTheme.bodyMedium),
                          Text(
                            '${Money.format(_unitPriceCents)} / ${_variant.unit}',
                            style: textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      if (_volumeDiscount)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: scheme.tertiaryContainer,
                              side: BorderSide.none,
                              avatar: Icon(Icons.local_offer_outlined,
                                  size: 15, color: scheme.onTertiaryContainer),
                              label: Text('Precio mayoreo aplicado',
                                  style: textTheme.labelSmall?.copyWith(
                                      color: scheme.onTertiaryContainer)),
                            ),
                          ),
                        ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total', style: textTheme.titleMedium),
                          Text(
                            Money.format(_totalCents),
                            style: textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // -------- display de cantidad --------
              Row(
                children: [
                  Text('Cantidad', style: textTheme.bodyMedium),
                  const Spacer(),
                  Text(
                    _qtyText.isEmpty ? '0' : _qtyText,
                    style: textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  Text(_variant.unit, style: textTheme.titleMedium),
                  IconButton(
                    tooltip: 'Limpiar',
                    icon: const Icon(Icons.backspace_outlined),
                    onPressed: _qtyText.isEmpty
                        ? null
                        : () => setState(() => _qtyText = ''),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // -------- atajos de cantidad --------
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, qty) in _shortcuts)
                    ActionChip(
                      label: Text(label),
                      onPressed: () => setState(() {
                        _qtyText = qty % 1 == 0
                            ? qty.toInt().toString()
                            : qty.toStringAsFixed(2);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // -------- teclado numérico propio --------
              NumericKeypad(
                value: _qtyText,
                onChanged: (v) => setState(() => _qtyText = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: _quantity > 0 ? _confirm : null,
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(_quantity > 0
                    ? 'Agregar ${Money.format(_totalCents)}'
                    : 'Agregar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
