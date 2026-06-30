import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/money.dart';
import '../../../domain/entities/catalog_item.dart';
import '../../../domain/entities/product_variant.dart';
import '../../providers.dart';
import 'break_variant_dialog.dart';
import 'import_wizard_sheet.dart';
import 'item_editor_sheet.dart';

/// Inventario de un vistazo: existencias por variante, márgenes y ajuste
/// rápido de stock (+/-) sin formularios. Los productos con varias
/// presentaciones se despliegan y pueden pasarse a granel (desensamble).
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogListProvider);

    return Scaffold(
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'inventory_import',
            tooltip: 'Importar desde Excel/CSV',
            onPressed: () => showImportWizardSheet(context),
            child: const Icon(Icons.upload_file),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'inventory_add',
            onPressed: () => showItemEditorSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Agregar'),
          ),
        ],
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _InventoryTile(item: items[i]),
        ),
      ),
    );
  }
}

class _InventoryTile extends ConsumerWidget {
  const _InventoryTile({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final product = item is Product ? item as Product : null;

    final marginPercent = item.salePriceCents == 0
        ? 0
        : (item.unitMarginCents * 100 / item.salePriceCents).round();

    final leading = CircleAvatar(
      backgroundColor:
          item.isService ? scheme.tertiaryContainer : scheme.primaryContainer,
      child: Icon(
        item.isService ? Icons.support_agent : Icons.inventory_2_outlined,
        color: item.isService
            ? scheme.onTertiaryContainer
            : scheme.onPrimaryContainer,
      ),
    );

    // Servicios y productos simples: fila plana como siempre.
    // Mantener presionado un producto abre "Pasar a granel" (y desde
    // ahí se puede crear su presentación granel).
    if (product == null || !product.hasMultipleVariants) {
      return ListTile(
        onTap: () => showItemEditorSheet(context, existing: item),
        onLongPress: product == null
            ? null
            : () => showBreakVariantDialog(context, product: product),
        leading: leading,
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${item.category} · Costo ${Money.format(item.costPriceCents)} · '
          'Venta ${Money.format(item.salePriceCents)} · Margen $marginPercent%',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: product == null
            ? const Chip(
                visualDensity: VisualDensity.compact,
                label: Text('Servicio'),
              )
            : _StockStepper(variant: product.defaultVariant),
      );
    }

    // Producto con presentaciones: desplegable con stock por cada una.
    return ExpansionTile(
      leading: leading,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${item.category} · ${product.sellableVariants.length} presentaciones',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
      children: [
        for (final variant in product.sellableVariants)
          ListTile(
            dense: true,
            title: Text(variant.name),
            subtitle: Text(
              'Costo ${Money.format(variant.costPriceCents)} · '
              'Venta ${Money.format(variant.salePriceCents)}'
              '${variant.priceTiers.isEmpty ? '' : ' · ${variant.priceTiers.length} escalón(es)'}',
            ),
            trailing: _StockStepper(variant: variant),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => showItemEditorSheet(context, existing: item),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () =>
                    showBreakVariantDialog(context, product: product),
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text('Granel'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Steppers de stock (+/-) de UNA variante; tocar el número permite
/// un ajuste de cantidad arbitraria (entrada de camión, merma).
class _StockStepper extends ConsumerWidget {
  const _StockStepper({required this.variant});

  final ProductVariant variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final lowStock = variant.stock <= AppConfig.lowStockThreshold;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Restar 1',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => _adjust(context, ref, -1),
        ),
        InkWell(
          onTap: () => _adjustCustom(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              variant.stock % 1 == 0
                  ? variant.stock.toInt().toString()
                  : variant.stock.toStringAsFixed(2),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: lowStock ? scheme.error : null,
                    fontWeight: lowStock ? FontWeight.bold : null,
                  ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Sumar 1',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _adjust(context, ref, 1),
        ),
      ],
    );
  }

  Future<void> _adjust(
      BuildContext context, WidgetRef ref, double delta) async {
    final result = await ref.read(catalogRepositoryProvider).adjustStock(
          variantId: variant.id,
          delta: delta,
          reason: 'ajuste_manual',
        );

    if (!context.mounted) return;
    refreshAfterMutation(ref);

    final message = result.failureOrNull?.message;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<void> _adjustCustom(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final delta = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(variant.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          decoration: const InputDecoration(
            labelText: 'Ajuste (+ entrada, - merma)',
            hintText: 'Ej. 20 o -2',
          ),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(double.tryParse(value)),
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

    if (delta == null || delta == 0 || !context.mounted) return;
    await _adjust(context, ref, delta);
  }
}
