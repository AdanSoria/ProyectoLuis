import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/money.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../domain/entities/delivery_person.dart';
import '../../../../domain/entities/transaction.dart';
import '../../../../domain/usecases/process_transaction_usecase.dart';
import '../../../providers.dart';

/// **Flujo de Reparto en 3 Pasos** — directamente desde el modal del
/// carrito, sin navegar a otras pantallas:
///
///   Paso 1 · Cliente    → chip de cliente reciente (1 toque) o captura rápida
///   Paso 2 · Repartidor → chip de repartidor (1 toque) o "sin asignar"
///   Paso 3 · Confirmar  → botón REGISTRAR PEDIDO (1 toque)
///
/// Camino feliz: **3 toques** para registrar y asignar un pedido telefónico.
Future<void> showDeliveryFlowSheet(BuildContext context) {
  final wide = MediaQuery.of(context).size.width >= 700;

  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => const Dialog(
        child: SizedBox(width: 480, height: 620, child: _DeliveryFlow()),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.92,
      child: _DeliveryFlow(),
    ),
  );
}

class _DeliveryFlow extends ConsumerStatefulWidget {
  const _DeliveryFlow();

  @override
  ConsumerState<_DeliveryFlow> createState() => _DeliveryFlowState();
}

class _DeliveryFlowState extends ConsumerState<_DeliveryFlow> {
  int _step = 0;

  SaleChannel _channel = SaleChannel.whatsapp;
  Customer? _selectedCustomer;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  DeliveryPerson? _deliveryPerson;
  bool _unassigned = false;

  final _notesController = TextEditingController();
  bool _processing = false;

  static const _titles = ['Cliente', 'Repartidor', 'Confirmar'];

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _customerName =>
      _selectedCustomer?.name ?? _nameController.text.trim();

  bool get _canContinueStep1 => _customerName.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                if (_step > 0)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _processing
                        ? null
                        : () => setState(() => _step -= 1),
                  ),
                Text(
                  'Paso ${_step + 1} de 3 · ${_titles[_step]}',
                  style: textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed:
                      _processing ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: i <= _step
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  if (i < 2) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
          Expanded(
            child: switch (_step) {
              0 => _buildCustomerStep(),
              1 => _buildDeliveryStep(),
              _ => _buildConfirmStep(),
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- paso 1: cliente

  Widget _buildCustomerStep() {
    final recent = ref.watch(recentCustomersProvider);
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<SaleChannel>(
          segments: const [
            ButtonSegment(
              value: SaleChannel.whatsapp,
              icon: Icon(Icons.chat_outlined),
              label: Text('WhatsApp'),
            ),
            ButtonSegment(
              value: SaleChannel.telefono,
              icon: Icon(Icons.call_outlined),
              label: Text('Teléfono'),
            ),
            ButtonSegment(
              value: SaleChannel.mostrador,
              icon: Icon(Icons.storefront_outlined),
              label: Text('Mostrador'),
            ),
          ],
          selected: {_channel},
          onSelectionChanged: (selection) =>
              setState(() => _channel = selection.first),
        ),
        const SizedBox(height: 16),
        Text('Clientes recientes (1 toque y sigue)',
            style: textTheme.labelLarge),
        const SizedBox(height: 8),
        recent.maybeWhen(
          data: (customers) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final customer in customers)
                ChoiceChip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(customer.name),
                  selected: _selectedCustomer?.id == customer.id,
                  onSelected: (_) {
                    setState(() {
                      _selectedCustomer = customer;
                      _step = 1; // avance automático: fricción cero
                    });
                  },
                ),
            ],
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        Text('…o captura rápida de cliente nuevo',
            style: textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          onChanged: (_) => setState(() => _selectedCustomer = null),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Teléfono (opcional)',
            prefixIcon: Icon(Icons.call_outlined),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _canContinueStep1
              ? () => setState(() => _step = 1)
              : null,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('CONTINUAR'),
        ),
      ],
    );
  }

  // ---------------------------------------------------- paso 2: repartidor

  Widget _buildDeliveryStep() {
    final people = ref.watch(deliveryPeopleProvider);
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Asignar a (1 toque y sigue)', style: textTheme.labelLarge),
        const SizedBox(height: 8),
        people.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('Error: $error'),
          data: (list) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final person in list)
                ChoiceChip(
                  avatar: const Icon(Icons.sports_motorsports_outlined,
                      size: 18),
                  label: Text(person.name),
                  selected: _deliveryPerson?.id == person.id,
                  onSelected: (_) {
                    setState(() {
                      _deliveryPerson = person;
                      _unassigned = false;
                      _step = 2; // avance automático
                    });
                  },
                ),
              ChoiceChip(
                avatar: const Icon(Icons.schedule, size: 18),
                label: const Text('Sin asignar (queda pendiente)'),
                selected: _unassigned,
                onSelected: (_) {
                  setState(() {
                    _deliveryPerson = null;
                    _unassigned = true;
                    _step = 2;
                  });
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo repartidor'),
                onPressed: _promptNewDeliveryPerson,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _promptNewDeliveryPerson() async {
    final person = await promptNewDeliveryPerson(context, ref);
    if (person != null && mounted) {
      setState(() {
        _deliveryPerson = person;
        _unassigned = false;
        _step = 2;
      });
    }
  }

  // ----------------------------------------------------- paso 3: confirmar

  Widget _buildConfirmStep() {
    final cart = ref.watch(cartProvider);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _phoneOrSelected() == null
                            ? _customerName
                            : '$_customerName · ${_phoneOrSelected()}',
                        style: textTheme.titleMedium,
                      ),
                    ),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(_channel.label),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    Icon(Icons.local_shipping_outlined,
                        size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      _deliveryPerson?.name ??
                          'Sin asignar · quedará PENDIENTE',
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final line in cart.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  line.quantity % 1 == 0
                      ? '${line.quantity.toInt()}×'
                      : '${line.quantity}×',
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(line.item.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text(Money.format(line.totalCents)),
              ],
            ),
          ),
        const Divider(),
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
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'Nota de entrega (opcional)',
            prefixIcon: Icon(Icons.sticky_note_2_outlined),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _processing ? null : _register,
          icon: _processing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.local_shipping),
          label: const Text('REGISTRAR PEDIDO'),
        ),
      ],
    );
  }

  String? _phoneOrSelected() {
    final phone = _selectedCustomer?.phone ?? _phoneController.text.trim();
    return phone.isEmpty ? null : phone;
  }

  Future<void> _register() async {
    setState(() => _processing = true);

    // Mini-CRM silencioso: el cliente capturado a mano se guarda para
    // aparecer como chip de "reciente" en el siguiente pedido.
    var customer = _selectedCustomer;
    if (customer == null && _nameController.text.trim().isNotEmpty) {
      final newCustomer = Customer(
        id: ref.read(idGeneratorProvider).newId(),
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        createdAt: DateTime.now().toUtc(),
      );
      final saved = await ref
          .read(customerRepositoryProvider)
          .save(newCustomer, isNew: true);
      customer = saved.valueOrNull ?? customer;
    }

    if (!mounted) return;

    final cart = ref.read(cartProvider);
    final result = await ref.read(processTransactionUseCaseProvider).call(
          ProcessTransactionInput(
            lines: cart.lines,
            kind: TransactionKind.pedido,
            channel: _channel,
            deductionsCents: cart.deductionsCents,
            customer: customer,
            customerName: _nameController.text,
            customerPhone: _phoneController.text,
            deliveryPerson: _deliveryPerson,
            notes: _notesController.text,
          ),
        );

    if (!mounted) return;

    result.fold(
      ok: (order) {
        ref.read(cartProvider.notifier).clear();
        refreshAfterMutation(ref);
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Pedido ${order.folio} registrado · ${order.status.label}',
          ),
        ));
      },
      err: (failure) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      },
    );
  }
}

// ---------------------------------------------------------------- reusables

/// Alta exprés de repartidor (un solo campo). Reutilizado por el flujo
/// de 3 pasos y por la pantalla de pedidos.
Future<DeliveryPerson?> promptNewDeliveryPerson(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Nuevo repartidor'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nombre o apodo'),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );

  if (name == null || name.trim().isEmpty) return null;

  final person = DeliveryPerson(
    id: ref.read(idGeneratorProvider).newId(),
    name: name.trim(),
  );
  final result =
      await ref.read(deliveryRepositoryProvider).save(person, isNew: true);

  ref.invalidate(deliveryPeopleProvider);
  return result.valueOrNull;
}

/// Selector rápido de repartidor para asignar desde la lista de pedidos.
Future<DeliveryPerson?> showDeliveryPersonPicker(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<DeliveryPerson>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => Consumer(
      builder: (_, sheetRef, __) {
        final people = sheetRef.watch(deliveryPeopleProvider);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Asignar repartidor',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 12),
              people.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text('Error: $error'),
                data: (list) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final person in list)
                      ActionChip(
                        avatar: const Icon(
                            Icons.sports_motorsports_outlined,
                            size: 18),
                        label: Text(person.name),
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(person),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Nuevo repartidor'),
                      onPressed: () async {
                        final person =
                            await promptNewDeliveryPerson(sheetContext, ref);
                        if (person != null && sheetContext.mounted) {
                          Navigator.of(sheetContext).pop(person);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    ),
  );
}
