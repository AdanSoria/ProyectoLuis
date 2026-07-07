import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/utils/money.dart';
import '../../../../domain/entities/catalog_item.dart';
import '../../../providers.dart';
import 'quantity_capture_sheet.dart';

/// Tarjeta del catálogo.
///
/// Interacción (fricción cero donde importa):
/// - Servicio o producto simple de pieza: **1 toque = 1 al carrito**.
///   Mantener presionado abre la hoja de cantidad (varias piezas).
/// - Producto de peso/volumen o con varias presentaciones: **1 toque abre
///   la hoja unificada** de captura (variante + cantidad + precio en vivo).
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
    // ¿La captura necesita cantidad/variante? (abre la hoja unificada)
    final needsSheet = product != null &&
        (multiVariant || AppConfig.isWeightVolume(product.defaultVariant.unit));

    void primaryAction() {
      if (product == null) {
        ref.read(cartProvider.notifier).add(item); // servicio: 1 toque
      } else if (needsSheet) {
        showQuantityCaptureSheet(context, ref, product: product);
      } else {
        ref.read(cartProvider.notifier).add(item); // pieza: 1 toque
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: (outOfStock && !multiVariant) ? null : primaryAction,
        onLongPress: (product == null || outOfStock)
            ? null
            : () => showQuantityCaptureSheet(context, ref, product: product),
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
}
