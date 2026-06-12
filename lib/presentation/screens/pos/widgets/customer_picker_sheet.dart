import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/money.dart';
import '../../../../domain/entities/customer.dart';
import '../../../providers.dart';

/// Selector rápido de cliente para el ticket: recientes + búsqueda.
/// Muestra la categoría y el descuento de perfil de cada cliente para
/// que el cajero sepa qué trato aplicará.
Future<Customer?> showCustomerPickerSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.7,
      child: _CustomerPicker(),
    ),
  );
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final repository = ref.read(customerRepositoryProvider);

    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Asignar cliente', style: textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o teléfono…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Customer>>(
                future: _query.isEmpty
                    ? repository.getRecent(30)
                    : repository.search(_query),
                builder: (context, snapshot) {
                  final customers = snapshot.data;
                  if (customers == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (customers.isEmpty) {
                    return const Center(
                        child: Text('Sin clientes que coincidan.'));
                  }
                  return ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (_, i) {
                      final customer = customers[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              customer.category == CustomerCategory.mayorista
                                  ? scheme.tertiaryContainer
                                  : scheme.primaryContainer,
                          child: Text(customer.name.isEmpty
                              ? '?'
                              : customer.name[0].toUpperCase()),
                        ),
                        title: Text(customer.name),
                        subtitle: Text([
                          customer.category.label,
                          if (customer.discountPercent > 0)
                            '${customer.discountPercent % 1 == 0 ? customer.discountPercent.toInt() : customer.discountPercent}% desc.',
                          if (customer.purchaseCount > 0)
                            '${customer.purchaseCount} compras · '
                                '${Money.format(customer.totalSpentCents)}',
                        ].join(' · ')),
                        onTap: () => Navigator.of(context).pop(customer),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
