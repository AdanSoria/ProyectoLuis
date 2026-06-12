import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/utils/money.dart';
import '../../../../domain/entities/catalog_item.dart';
import '../../../../domain/entities/product_variant.dart';
import '../../../providers.dart';

/// Tarjeta del catálogo. **Un tap = un artículo al carrito.**
/// Mantener presionado abre captura rápida de cantidad (bultos, kg).
class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final product = item is Product ? item as Product : null;
    final outOfStock = product != null && product.stock <= 0;
    final lowStock = product != null &&
        !outOfStock &&
        product.stock <= AppConfig.lowStockThreshold;

    final multiVariant = product != null && product.hasMultipleVariants;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: outOfStock && !multiVariant
            ? null
            : () => multiVariant
                ? _pickVariant(context, ref, product)
                : ref.read(cartProvider.notifier).add(item),
        onLongPress: outOfStock || multiVariant
            ? null
            : () => _askQuantity(context, ref, null),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: item.isService
                        ? scheme.tertiaryContainer
                        : scheme.primaryContainer,
                    child: Icon(
                      item.isService
                          ? Icons.support_agent
                          : Icons.inventory_2_outlined,
                      size: 18,
                      color: item.isService
                          ? scheme.onTertiaryContainer
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        multiVariant
                            ? 'desde ${Money.format(product.minSalePriceCents)}'
                            : Money.format(item.salePriceCents),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 4),
              if (item.isService)
                Text(
                  'Servicio · sin stock',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.tertiary),
                )
              else if (multiVariant)
                Text(
                  '${product.sellableVariants.length} presentaciones',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.primary),
                )
              else
                Text(
                  outOfStock
                      ? 'Agotado'
                      : 'Stock: ${_formatStock(product!.stock)} ${item.unit}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: outOfStock || lowStock
                            ? scheme.error
                            : scheme.outline,
                        fontWeight:
                            lowStock || outOfStock ? FontWeight.bold : null,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatStock(double stock) =>
      stock % 1 == 0 ? stock.toInt().toString() : stock.toStringAsFixed(2);

  /// Selector de presentación: 1 toque sobre la variante = al carrito.
  Future<void> _pickVariant(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name,
                style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final variant in product.sellableVariants)
                  ActionChip(
                    avatar: Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: variant.stock <= 0
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                    label: Text(
                      '${variant.name} · ${Money.format(variant.salePriceCents)}'
                      ' · ${_formatStock(variant.stock)} ${variant.unit}',
                    ),
                    onPressed: variant.stock <= 0
                        ? null
                        : () {
                            ref
                                .read(cartProvider.notifier)
                                .add(item, variant: variant);
                            Navigator.of(sheetContext).pop();
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Captura rápida de cantidad para venta a granel o por bulto.
  Future<void> _askQuantity(
    BuildContext context,
    WidgetRef ref,
    ProductVariant? variant,
  ) async {
    final unit = variant?.unit ?? item.unit;
    final controller = TextEditingController();
    final quantity = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(variant == null ? item.name : '${item.name} · ${variant.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Cantidad ($unit)',
            hintText: 'Ej. 3',
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
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (quantity != null && quantity > 0) {
      ref
          .read(cartProvider.notifier)
          .add(item, variant: variant, quantity: quantity);
    }
  }
}
