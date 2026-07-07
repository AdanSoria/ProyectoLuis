import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/money.dart';
import '../../../../domain/entities/cart_line.dart';
import '../../../../domain/entities/catalog_item.dart';
import '../../../providers.dart';
import 'charge_dialog.dart';
import 'customer_picker_sheet.dart';
import 'delivery_flow_sheet.dart';
import 'free_item_dialog.dart';

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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Barra de acciones rápidas (siempre visible) ----
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _TicketAction(
                        icon: cart.customer == null
                            ? Icons.person_add_alt
                            : Icons.person,
                        label: cart.customer?.name ?? 'Cliente',
                        highlighted: cart.customer != null,
                        onTap: () => _pickCustomer(context, ref),
                        onClear: cart.customer == null
                            ? null
                            : () => ref
                                .read(cartProvider.notifier)
                                .setCustomer(null),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: _TicketAction(
                        icon: Icons.percent,
                        label: cart.deductionsCents == 0
                            ? 'Descuento'
                            : '-${Money.format(cart.deductionsCents)}',
                        highlighted: cart.deductionsCents > 0,
                        onTap: cart.isEmpty
                            ? null
                            : () => _askDiscount(context, ref),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: _TicketAction(
                        icon: Icons.add_box_outlined,
                        label: 'Ítem libre',
                        onTap: () => showFreeItemDialog(context, ref),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtotal', style: textTheme.bodyMedium),
                    Text(Money.format(cart.subtotalCents),
                        style: textTheme.bodyMedium),
                  ],
                ),
                if (cart.deductionsCents > 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cart.isManualDiscount
                            ? 'Descuento manual'
                            : 'Descuento cliente',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: scheme.tertiary),
                      ),
                      Text('-${Money.format(cart.deductionsCents)}',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: scheme.tertiary)),
                    ],
                  ),
                ],
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

  /// Descuento flexible al momento: por **porcentaje** (chips rápidos o
  /// libre) o por **monto directo en pesos** — porque en mostrador el
  /// trato varía venta a venta. El historial queda intacto: solo cambia
  /// la deducción del ticket.
  Future<void> _askDiscount(BuildContext context, WidgetRef ref) async {
    final cart = ref.read(cartProvider);
    final controller = TextEditingController();
    var asPercent = true;

    final result = await showDialog<(bool, int)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) {
          int centsFromInput() {
            if (!asPercent) return Money.fromText(controller.text);
            final pct = double.tryParse(
                    controller.text.replaceAll(',', '.').trim()) ??
                0;
            return (cart.subtotalCents * pct.clamp(0, 100) / 100).round();
          }

          final preview = centsFromInput();

          return AlertDialog(
            title: const Text('Descuento del ticket'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cart.customer != null &&
                    cart.customer!.discountPercent > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Perfil del cliente: '
                      '${_percent(cart.customer!.discountPercent)}% '
                      '(${Money.format(cart.autoDiscountCents)})',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.percent),
                      label: Text('Porcentaje'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.attach_money),
                      label: Text('Monto'),
                    ),
                  ],
                  selected: {asPercent},
                  onSelectionChanged: (selection) => setLocal(() {
                    asPercent = selection.first;
                    controller.clear();
                  }),
                ),
                const SizedBox(height: 12),
                if (asPercent)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final pct in const [5, 10, 15, 20])
                        ActionChip(
                          label: Text('$pct%'),
                          onPressed: () =>
                              setLocal(() => controller.text = '$pct'),
                        ),
                    ],
                  ),
                if (asPercent) const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText:
                        asPercent ? 'Porcentaje' : 'Monto en pesos',
                    prefixText: asPercent ? null : r'$ ',
                    suffixText: asPercent ? '%' : null,
                  ),
                  onChanged: (_) => setLocal(() {}),
                  onSubmitted: (_) => Navigator.of(dialogContext)
                      .pop((false, centsFromInput())),
                ),
                const SizedBox(height: 8),
                Text(
                  'Descuento: ${Money.format(preview)} · '
                  'Total: ${Money.format((cart.subtotalCents - preview).clamp(0, cart.subtotalCents))}',
                  style: Theme.of(dialogContext)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop((true, 0)),
                child: Text(cart.customer != null
                    ? 'Usar el del cliente'
                    : 'Sin descuento'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext)
                    .pop((false, centsFromInput())),
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;
    final (useAuto, cents) = result;
    ref
        .read(cartProvider.notifier)
        .setManualDeductions(useAuto ? null : cents);
  }
}

bool _isFreeItem(CatalogItem item) =>
    item is Service && item.category == kFreeItemCategory;

/// Botón compacto de la barra de acciones del ticket (Cliente / Descuento
/// / Ítem libre). Muestra ícono + etiqueta truncable y, opcionalmente, una
/// "x" para limpiar (quitar cliente).
class _TicketAction extends StatelessWidget {
  const _TicketAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onClear,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final fg = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
        : highlighted
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant;

    return Material(
      color: highlighted ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: fg),
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(Icons.close, size: 16, color: fg),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiqueta compacta para el ticket (regla de precio, "Libre"…).
class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.background,
    required this.onColor,
  });

  final String label;
  final Color background;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: onColor, fontWeight: FontWeight.w600),
      ),
    );
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
                Row(
                  children: [
                    Flexible(
                      child: Text(line.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium),
                    ),
                    if (_isFreeItem(line.item)) ...[
                      const SizedBox(width: 6),
                      _Tag(
                        label: 'Libre',
                        background: scheme.tertiaryContainer,
                        onColor: scheme.onTertiaryContainer,
                      ),
                    ],
                  ],
                ),
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
