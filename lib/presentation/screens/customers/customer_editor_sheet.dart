import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../core/utils/time_ago.dart';
import '../../../domain/entities/customer.dart';
import '../../providers.dart';

/// Alta/edición exprés de cliente: perfil comercial completo
/// (categoría, % de descuento base) sin formularios pesados.
Future<void> showCustomerEditorSheet(BuildContext context,
    {Customer? existing}) {
  final wide = MediaQuery.of(context).size.width >= 700;

  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child:
            SizedBox(width: 440, child: _CustomerEditor(existing: existing)),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _CustomerEditor(existing: existing),
    ),
  );
}

class _CustomerEditor extends ConsumerStatefulWidget {
  const _CustomerEditor({this.existing});

  final Customer? existing;

  @override
  ConsumerState<_CustomerEditor> createState() => _CustomerEditorState();
}

class _CustomerEditorState extends ConsumerState<_CustomerEditor> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  late final TextEditingController _discount;
  late CustomerCategory _category;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _discount = TextEditingController(
        text: existing == null || existing.discountPercent == 0
            ? ''
            : (existing.discountPercent % 1 == 0
                ? existing.discountPercent.toInt().toString()
                : existing.discountPercent.toString()));
    _category = existing?.category ?? CustomerCategory.minorista;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    _discount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final existing = widget.existing;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isNew ? 'Nuevo cliente' : 'Editar cliente',
                style: textTheme.titleLarge),
            if (existing != null && existing.purchaseCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Historial: ${existing.purchaseCount} compras · '
                '${Money.format(existing.totalSpentCents)} · '
                'ticket promedio ${Money.format(existing.averageTicketCents)}'
                '${existing.lastPurchaseAt == null ? '' : ' · última ${timeAgo(existing.lastPurchaseAt!)}'}',
                style: textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Teléfono (opcional)'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<CustomerCategory>(
              segments: const [
                ButtonSegment(
                  value: CustomerCategory.minorista,
                  icon: Icon(Icons.person_outline),
                  label: Text('Minorista'),
                ),
                ButtonSegment(
                  value: CustomerCategory.mayorista,
                  icon: Icon(Icons.store_outlined),
                  label: Text('Mayorista'),
                ),
              ],
              selected: {_category},
              onSelectionChanged: (selection) =>
                  setState(() => _category = selection.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _discount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Descuento base (%)',
                helperText:
                    'Se aplica solo al asignarlo a una venta (anulable)',
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                  labelText: 'Notas / dirección (opcional)'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed:
                  _saving || _name.text.trim().isEmpty ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_isNew ? 'GUARDAR' : 'GUARDAR CAMBIOS'),
            ),
            TextButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final discount =
        (double.tryParse(_discount.text.replaceAll(',', '.')) ?? 0)
            .clamp(0.0, 100.0);
    final existing = widget.existing;

    final customer = Customer(
      id: existing?.id ?? ref.read(idGeneratorProvider).newId(),
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      category: _category,
      discountPercent: discount,
      totalSpentCents: existing?.totalSpentCents ?? 0,
      purchaseCount: existing?.purchaseCount ?? 0,
      lastPurchaseAt: existing?.lastPurchaseAt,
      createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
    );

    final result = await ref
        .read(customerRepositoryProvider)
        .save(customer, isNew: _isNew);

    if (!mounted) return;

    result.fold(
      ok: (saved) {
        refreshAfterMutation(ref);
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Cliente "${saved.name}" guardado.')),
        );
      },
      err: (failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      },
    );
  }
}
