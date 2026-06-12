import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/money.dart';
import '../../../../domain/entities/cart_line.dart';
import '../../../providers.dart';
import 'charge_dialog.dart';
import 'customer_picker_sheet.dart';
import 'delivery_flow_sheet.dart';

/// Ticket de cobro (lado derecho del mostrador).
/// Carrito interactivo: cliente con descuento de perfil, steppers de
/// cantidad, regateo por línea (mantener presionado el precio) y dos
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
          // ------------------------------------------------ cliente (CRM)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: cart.customer == null
                  ? ActionChip(
                      avatar: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('Asignar cliente'),
                      onPressed: () => _pickCustomer(context, ref),
                    )
                  : InputChip(
                      avatar: const Icon(Icons.person, size: 18),
                      label: Text(
                        cart.customer!.discountPercent > 0
                            ? '${cart.customer!.name} · '
                                '${cart.customer!.category.label} '
                                '${_percent(cart.customer!.discountPercent)}%'
                            : cart.customer!.name,
                      ),
                      onPressed: () => _pickCustomer(context, ref),
                      onDeleted: () =>
                          ref.read(cartProvider.notifier).setCustomer(null),
                    ),
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
                    itemBuilder: (context, i) =>
                        _LineRow(line: cart.lines[i]),
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
                      label: Text(
                        cart.isManualDiscount
                            ? 'Descuento manual'
                            : cart.autoDiscountCents > 0
                                ? 'Descuento cliente'
                                : 'Descuento',
                      ),
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

  String _percent(double value) => value % 1 == 0
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  Future<void> _pickCustomer(BuildContext context, WidgetRef ref) async {
    final customer = await showCustomerPickerSheet(context, ref);
    if (customer != null) {
      ref.read(cartProvider.notifier).setCustomer(customer);
    }
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
    final cart = ref.read(cartProvider);
    final controller = TextEditingController();
    final result = await showDialog<(bool, int)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descuento del ticket'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cart.customer != null && cart.customer!.discountPercent > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Perfil del cliente: '
                  '${_percent(cart.customer!.discountPercent)}% '
                  '(${Money.format(cart.autoDiscountCents)})',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monto manual en pesos',
                prefixText: r'$ ',
              ),
              onSubmitted: (value) => Navigator.of(dialogContext)
                  .pop((false, Money.fromText(value))),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop((true, 0)),
            child: Text(cart.customer != null
                ? 'Usar el del cliente'
                : 'Sin descuento'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop((false, Money.fromText(controller.text))),
            child: const Text('Aplicar manual'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final (useAuto, cents) = result;
    ref
        .read(cartProvider.notifier)
        .setManualDeductions(useAuto ? null : cents);
  }
}

class _LineRow extends ConsumerWidget {
  const _LineRow({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium),
                // Mantener presionado el precio = regateo.
                InkWell(
                  onLongPress: () => _negotiatePrice(context, ref),
                  child: Text(
                    line.hasOverride
                        ? '${Money.format(line.unitPriceCents)} '
                            '(lista ${Money.format(line.listUnitPriceCents)})'
                        : '${Money.format(line.unitPriceCents)} '
                            '· ${line.effectiveVariant?.unit ?? line.item.unit}',
                    style: textTheme.labelSmall?.copyWith(
                      color:
                          line.hasOverride ? scheme.tertiary : scheme.outline,
                      fontWeight: line.hasOverride ? FontWeight.bold : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => ref.read(cartProvider.notifier).decrement(line),
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
            onPressed: () => ref.read(cartProvider.notifier).increment(line),
          ),
          SizedBox(
            width: 78,
            child: InkWell(
              onLongPress: () => _negotiatePrice(context, ref),
              child: Text(
                Money.format(line.totalCents),
                textAlign: TextAlign.end,
                style:
                    textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Sobreescritura de precio ("Manual Override") para regateo rápido.
  Future<void> _negotiatePrice(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
        text: (line.unitPriceCents / 100).toStringAsFixed(2));
    final result = await showDialog<(bool, int)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(line.displayName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Precio de lista: ${Money.format(line.listUnitPriceCents)}',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Precio negociado (por unidad)',
                prefixText: r'$ ',
              ),
              onSubmitted: (value) => Navigator.of(dialogContext)
                  .pop((false, Money.fromText(value))),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop((true, 0)),
            child: const Text('Volver a lista'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop((false, Money.fromText(controller.text))),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final (resetToList, cents) = result;
    ref
        .read(cartProvider.notifier)
        .setPriceOverride(line, resetToList || cents <= 0 ? null : cents);
  }
}
