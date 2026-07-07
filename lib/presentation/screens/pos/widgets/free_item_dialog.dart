import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/money.dart';
import '../../../../domain/entities/catalog_item.dart';
import '../../../providers.dart';

/// Marcador de categoría para ítems cobrados sin estar en el catálogo.
/// Permite distinguirlos en el ticket (chip "Libre") y en los reportes
/// sin necesidad de una FK: la línea se guarda como snapshot libre.
const String kFreeItemCategory = '__libre__';

/// **Ítem libre**: cobra algo que no está en el catálogo sin salir del
/// mostrador. Opcionalmente lo guarda en el catálogo para futuras ventas.
Future<void> showFreeItemDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      child: SizedBox(width: 420, child: _FreeItemContent()),
    ),
  );
}

class _FreeItemContent extends ConsumerStatefulWidget {
  const _FreeItemContent();

  @override
  ConsumerState<_FreeItemContent> createState() => _FreeItemContentState();
}

class _FreeItemContentState extends ConsumerState<_FreeItemContent> {
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController(text: '1');
  bool _byWeight = false;
  bool _saveToCatalog = false;
  bool _busy = false;

  @override
  void dispose() {
    _desc.dispose();
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  String get _unit => _byWeight ? 'kg' : 'pieza';

  bool get _valid =>
      _desc.text.trim().isNotEmpty &&
      Money.fromText(_price.text) > 0 &&
      (double.tryParse(_qty.text.replaceAll(',', '.')) ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sell_outlined),
              const SizedBox(width: 8),
              Text('Ítem libre', style: textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 4),
          Text('Cobra algo que no está en el catálogo.',
              style: textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _desc,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Descripción'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Precio por $_unit',
                    prefixText: r'$ ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _qty,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('¿Se cobra por peso/volumen?'),
            subtitle: Text('Unidad: $_unit'),
            value: _byWeight,
            onChanged: (v) => setState(() => _byWeight = v),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Guardar en catálogo para futuras ventas'),
            value: _saveToCatalog,
            onChanged: (v) => setState(() => _saveToCatalog = v ?? false),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _valid && !_busy ? _add : null,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_shopping_cart),
            label: const Text('AGREGAR AL TICKET'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    setState(() => _busy = true);

    final now = DateTime.now().toUtc();
    final id = ref.read(idGeneratorProvider).newId();
    final name = _desc.text.trim();
    final priceCents = Money.fromText(_price.text);
    final quantity = double.parse(_qty.text.replaceAll(',', '.'));

    CatalogItem item;
    if (_saveToCatalog) {
      // Alta real en catálogo (mismo camino que Inventario). Peso/volumen
      // → producto con inventario (stock 0); si no → servicio sin stock.
      item = _byWeight
          ? Product.simple(
              id: id,
              name: name,
              category: 'Varios',
              costPriceCents: 0,
              salePriceCents: priceCents,
              unit: _unit,
              stock: 0,
              createdAt: now,
              updatedAt: now,
            )
          : Service(
              id: id,
              name: name,
              category: 'Varios',
              costPriceCents: 0,
              salePriceCents: priceCents,
              createdAt: now,
              updatedAt: now,
            );
      final saved =
          await ref.read(catalogRepositoryProvider).save(item, isNew: true);
      if (!mounted) return;
      final failure = saved.failureOrNull;
      if (failure != null) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
        return;
      }
      item = saved.valueOrNull!;
      refreshAfterMutation(ref);
    } else {
      // Efímero: servicio marcado como libre, sin fila en catálogo. La
      // venta lo guarda como snapshot (item_id sin FK) y no toca stock.
      item = Service(
        id: id,
        name: name,
        category: kFreeItemCategory,
        costPriceCents: 0,
        salePriceCents: priceCents,
        unit: _unit,
        createdAt: now,
        updatedAt: now,
      );
    }

    ref.read(cartProvider.notifier).add(item, quantity: quantity);

    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
