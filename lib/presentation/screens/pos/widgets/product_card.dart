import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/utils/money.dart';
import '../../../../domain/entities/catalog_item.dart';
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: outOfStock
            ? null
            : () => ref.read(cartProvider.notifier).add(item),
        onLongPress:
            outOfStock ? null : () => _askQuantity(context, ref),
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
                  const Spacer(),
                  Text(
                    Money.format(item.salePriceCents),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
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

  /// Captura rápida de cantidad para venta a granel o por bulto.
  Future<void> _askQuantity(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final quantity = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Cantidad (${item.unit})',
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
      ref.read(cartProvider.notifier).add(item, quantity);
    }
  }
}
