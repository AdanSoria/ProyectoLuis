import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/money.dart';
import '../../../providers.dart';
import 'charge_dialog.dart';
import 'delivery_flow_sheet.dart';

/// Ticket de cobro (lado derecho del mostrador).
/// Carrito interactivo: steppers de cantidad, descuento rápido y dos
/// acciones grandes: COBRAR (mostrador) o PEDIDO (flujo de reparto).
class TicketPanel extends ConsumerWidget {
  const TicketPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Icon(Icons.receipt_long, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Ticket', style: textTheme.titleLarge),
                const Spacer(),
                if (cart.isNotEmpty)
                  IconButton(
                    tooltip: 'Vaciar carrito',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => _confirmClear(context, ref),
                  ),
              ],
            ),
          ),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 48, color: scheme.outlineVariant),
                        const SizedBox(height: 8),
                        Text(
                          'Toca un producto\npara empezar a vender',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: scheme.outline),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final line = cart.lines[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(line.item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodyMedium),
                                  Text(
                                    '${Money.format(line.item.salePriceCents)} '
                                    '· ${line.item.unit}',
                                    style: textTheme.labelSmall
                                        ?.copyWith(color: scheme.outline),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => ref
                                  .read(cartProvider.notifier)
                                  .decrement(line.item.id),
                            ),
                            Text(
                              line.quantity % 1 == 0
                                  ? line.quantity.toInt().toString()
                                  : line.quantity.toStringAsFixed(2),
                              style: textTheme.titleMedium,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => ref
                                  .read(cartProvider.notifier)
                                  .increment(line.item.id),
                            ),
                            SizedBox(
                              width: 78,
                              child: Text(
                                Money.format(line.totalCents),
                                textAlign: TextAlign.end,
                                style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtotal', style: textTheme.bodyMedium),
                    Text(Money.format(cart.subtotalCents),
                        style: textTheme.bodyMedium),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact),
                      onPressed: cart.isEmpty
                          ? null
                          : () => _askDiscount(context, ref),
                      icon: const Icon(Icons.percent, size: 16),
                      label: const Text('Descuento'),
                    ),
                    Text(
                      cart.deductionsCents == 0
                          ? '—'
                          : '-${Money.format(cart.deductionsCents)}',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.tertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('TOTAL', style: textTheme.titleLarge),
                    Text(
                      Money.format(cart.totalCents),
                      style: textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: cart.isEmpty
                      ? null
                      : () => showChargeDialog(context, ref),
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('COBRAR'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: cart.isEmpty
                      ? null
                      : () => showDeliveryFlowSheet(context),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('PEDIDO / REPARTO'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Vaciar el carrito?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clear();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Sí, vaciar'),
          ),
        ],
      ),
    );
  }

  Future<void> _askDiscount(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final cents = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descuento del ticket'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Monto en pesos',
            prefixText: r'$ ',
          ),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(Money.fromText(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(0),
            child: const Text('Quitar descuento'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(Money.fromText(controller.text)),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );

    if (cents != null) {
      ref.read(cartProvider.notifier).setDeductions(cents);
    }
  }
}
