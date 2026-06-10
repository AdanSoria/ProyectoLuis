import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../core/utils/time_ago.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers.dart';
import '../pos/widgets/delivery_flow_sheet.dart';

/// Tablero de pedidos multicanal. Refleja la máquina de estados:
/// `pendiente -> asignado -> completado` (con cancelación y restock).
/// Cada tarjeta ofrece SOLO la acción válida para su estado.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  OrderStatus? _filter = OrderStatus.pendiente;

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider(_filter));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<OrderStatus?>(
                    segments: const [
                      ButtonSegment(
                          value: OrderStatus.pendiente,
                          label: Text('Pendientes')),
                      ButtonSegment(
                          value: OrderStatus.asignado,
                          label: Text('Asignados')),
                      ButtonSegment(
                          value: OrderStatus.completado,
                          label: Text('Completados')),
                      ButtonSegment(value: null, label: Text('Todos')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (selection) =>
                        setState(() => _filter = selection.first),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(ordersProvider),
              ),
            ],
          ),
        ),
        Expanded(
          child: orders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
            data: (list) => list.isEmpty
                ? const Center(child: Text('No hay pedidos en este estado.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _OrderCard(order: list[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});

  final Transaction order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final (IconData statusIcon, Color statusColor) = switch (order.status) {
      OrderStatus.pendiente => (Icons.schedule, scheme.tertiary),
      OrderStatus.asignado => (Icons.sports_motorsports, scheme.primary),
      OrderStatus.completado => (Icons.check_circle, scheme.primary),
      OrderStatus.cancelado => (Icons.cancel, scheme.error),
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.folio} · ${order.customerName ?? 'Mostrador'}',
                        style: textTheme.titleMedium,
                      ),
                      Text(
                        [
                          order.channel.label,
                          if (order.deliveryPersonName != null)
                            order.deliveryPersonName!,
                          timeAgo(order.createdAt),
                        ].join(' · '),
                        style: textTheme.labelSmall
                            ?.copyWith(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Money.format(order.totalCents),
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(order.status.label,
                        style: textTheme.labelSmall
                            ?.copyWith(color: statusColor)),
                  ],
                ),
              ],
            ),
            if (order.notes != null) ...[
              const SizedBox(height: 4),
              Text('Nota: ${order.notes}',
                  style:
                      textTheme.bodySmall?.copyWith(color: scheme.outline)),
            ],
            const SizedBox(height: 4),
            Text(
              [
                for (final line in order.lines)
                  '${line.quantity % 1 == 0 ? line.quantity.toInt() : line.quantity}× ${line.itemName}',
              ].join('  ·  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
            if (!order.status.isFinal) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _cancel(context, ref),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  if (order.status == OrderStatus.pendiente)
                    FilledButton.tonalIcon(
                      onPressed: () => _assign(context, ref),
                      icon: const Icon(Icons.sports_motorsports_outlined,
                          size: 18),
                      label: const Text('Asignar'),
                    ),
                  if (order.status == OrderStatus.asignado) ...[
                    OutlinedButton.icon(
                      onPressed: () => _assign(context, ref),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Reasignar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _complete(context, ref),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Entregado'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    final person = await showDeliveryPersonPicker(context, ref);
    if (person == null || !context.mounted) return;

    final result = await ref
        .read(assignOrderUseCaseProvider)
        .call(orderId: order.id, deliveryPerson: person);

    if (!context.mounted) return;
    _notify(context, ref,
        result.fold(ok: (o) => 'Pedido ${o.folio} asignado a ${person.name}.', err: (f) => f.message),
        isError: !result.isOk);
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final method = await _askPaymentMethod(context);
    if (method == null || !context.mounted) return;

    final result = await ref
        .read(completeOrderUseCaseProvider)
        .call(orderId: order.id, paymentMethod: method);

    if (!context.mounted) return;
    _notify(context, ref,
        result.fold(
            ok: (o) =>
                'Pedido ${o.folio} completado · ${Money.format(o.totalCents)} cobrados.',
            err: (f) => f.message),
        isError: !result.isOk);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Cancelar el pedido ${order.folio}?'),
        content: const Text(
            'Las existencias de los productos regresarán al inventario.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result =
        await ref.read(cancelOrderUseCaseProvider).call(orderId: order.id);

    if (!context.mounted) return;
    _notify(context, ref,
        result.fold(
            ok: (o) => 'Pedido ${o.folio} cancelado; stock devuelto.',
            err: (f) => f.message),
        isError: !result.isOk);
  }

  Future<PaymentMethod?> _askPaymentMethod(BuildContext context) {
    return showDialog<PaymentMethod>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('¿Cómo pagó el cliente?'),
        children: [
          for (final method in const [
            PaymentMethod.efectivo,
            PaymentMethod.tarjeta,
            PaymentMethod.transferencia,
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(method),
              child: Row(
                children: [
                  Icon(switch (method) {
                    PaymentMethod.efectivo => Icons.payments_outlined,
                    PaymentMethod.tarjeta => Icons.credit_card,
                    _ => Icons.swap_horiz,
                  }),
                  const SizedBox(width: 12),
                  Text(method.label),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _notify(BuildContext context, WidgetRef ref, String message,
      {required bool isError}) {
    refreshAfterMutation(ref);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor:
          isError ? Theme.of(context).colorScheme.error : null,
    ));
  }
}
