import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/money.dart';
import '../../../domain/entities/catalog_item.dart';
import '../../providers.dart';
import 'item_editor_sheet.dart';

/// Inventario de un vistazo: existencias, márgenes y ajuste rápido de
/// stock (+/-) sin formularios. Resalta el stock bajo.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogListProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showItemEditorSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
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
    final lowStock =
        product != null && product.stock <= AppConfig.lowStockThreshold;

    final marginPercent = item.salePriceCents == 0
        ? 0
        : (item.unitMarginCents * 100 / item.salePriceCents).round();

    return ListTile(
      onTap: () => showItemEditorSheet(context, existing: item),
      leading: CircleAvatar(
        backgroundColor: item.isService
            ? scheme.tertiaryContainer
            : scheme.primaryContainer,
        child: Icon(
          item.isService ? Icons.support_agent : Icons.inventory_2_outlined,
          color: item.isService
              ? scheme.onTertiaryContainer
              : scheme.onPrimaryContainer,
        ),
      ),
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
          : Row(
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Text(
                      product.stock % 1 == 0
                          ? product.stock.toInt().toString()
                          : product.stock.toStringAsFixed(2),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
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
            ),
    );
  }

  Future<void> _adjust(
      BuildContext context, WidgetRef ref, double delta) async {
    final result = await ref.read(catalogRepositoryProvider).adjustStock(
          productId: item.id,
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

  /// Entrada de mercancía: sumar una cantidad arbitraria (llegó camión).
  Future<void> _adjustCustom(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final delta = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: true),
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
