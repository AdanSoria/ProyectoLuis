import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/money.dart';
import '../../../../domain/entities/transaction.dart';
import '../../../../domain/usecases/process_transaction_usecase.dart';
import '../../../providers.dart';

/// Cobro de mostrador en 2 toques: método + CONFIRMAR.
/// Montos rápidos para efectivo y cambio calculado en vivo.
Future<void> showChargeDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      child: SizedBox(width: 420, child: _ChargeContent()),
    ),
  );
}

class _ChargeContent extends ConsumerStatefulWidget {
  const _ChargeContent();

  @override
  ConsumerState<_ChargeContent> createState() => _ChargeContentState();
}

class _ChargeContentState extends ConsumerState<_ChargeContent> {
  PaymentMethod _method = PaymentMethod.efectivo;
  late int _receivedCents;
  late final TextEditingController _receivedController;
  bool _processing = false;

  int get _totalCents => ref.read(cartProvider).totalCents;

  @override
  void initState() {
    super.initState();
    _receivedCents = _totalCents;
    _receivedController =
        TextEditingController(text: (_totalCents / 100).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _receivedController.dispose();
    super.dispose();
  }

  void _setReceived(int cents) {
    setState(() {
      _receivedCents = cents;
      _receivedController.text = (cents / 100).toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCash = _method == PaymentMethod.efectivo;
    final change = isCash ? _receivedCents - cart.totalCents : 0;
    final canCharge = !_processing && (!isCash || change >= 0);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cobrar', style: textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            Money.format(cart.totalCents),
            textAlign: TextAlign.center,
            style:
                textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SegmentedButton<PaymentMethod>(
            segments: const [
              ButtonSegment(
                value: PaymentMethod.efectivo,
                icon: Icon(Icons.payments_outlined),
                label: Text('Efectivo'),
              ),
              ButtonSegment(
                value: PaymentMethod.tarjeta,
                icon: Icon(Icons.credit_card),
                label: Text('Tarjeta'),
              ),
              ButtonSegment(
                value: PaymentMethod.transferencia,
                icon: Icon(Icons.swap_horiz),
                label: Text('Transf.'),
              ),
            ],
            selected: {_method},
            onSelectionChanged: (selection) =>
                setState(() => _method = selection.first),
          ),
          const SizedBox(height: 16),
          if (isCash) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Exacto'),
                  onPressed: () => _setReceived(cart.totalCents),
                ),
                for (final pesos in const [100, 200, 500, 1000])
                  ActionChip(
                    label: Text('\$$pesos'),
                    onPressed: () => _setReceived(pesos * 100),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _receivedController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Recibido',
                prefixText: r'$ ',
              ),
              onChanged: (value) =>
                  setState(() => _receivedCents = Money.fromText(value)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Cambio', style: textTheme.titleMedium),
                Text(
                  change >= 0 ? Money.format(change) : 'Falta dinero',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: change >= 0 ? scheme.primary : scheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          FilledButton.icon(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: canCharge ? _charge : null,
            icon: _processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: const Text('CONFIRMAR COBRO'),
          ),
          TextButton(
            onPressed:
                _processing ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _charge() async {
    setState(() => _processing = true);

    final cart = ref.read(cartProvider);
    final result = await ref.read(processTransactionUseCaseProvider).call(
          ProcessTransactionInput(
            lines: cart.lines,
            kind: TransactionKind.ventaMostrador,
            channel: SaleChannel.mostrador,
            paymentMethod: _method,
            amountPaidCents:
                _method == PaymentMethod.efectivo ? _receivedCents : 0,
            deductionsCents: cart.deductionsCents,
          ),
        );

    if (!mounted) return;

    result.fold(
      ok: (transaction) {
        ref.read(cartProvider.notifier).clear();
        refreshAfterMutation(ref);
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Venta ${transaction.folio} cobrada · '
            'Cambio: ${Money.format(transaction.changeCents)}',
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
