import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../core/utils/time_ago.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers.dart';
import 'customer_editor_sheet.dart';

/// Mini-CRM: cartera de clientes con su perfil comercial y la analítica
/// local (top de compradores, canales y categorías) calculada en SQLite.
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customerListProvider);
    final insights = ref.watch(customerInsightsProvider);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'customer_add',
        onPressed: () => showCustomerEditorSheet(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Nuevo cliente'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          // ------------------------------------------------ analítica local
          insights.maybeWhen(
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.topBuyers.isNotEmpty) ...[
                  Text('Top de compradores', style: textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (final (index, buyer)
                            in data.topBuyers.take(5).indexed)
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 14,
                              child: Text('${index + 1}'),
                            ),
                            title: Text(buyer.name),
                            subtitle: Text(
                              '${buyer.purchases} compras · ticket promedio '
                              '${Money.format(buyer.averageTicketCents)}',
                            ),
                            trailing: Text(
                              Money.format(buyer.totalCents),
                              style: textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (data.byChannel.isNotEmpty || data.topCategories.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final channel in data.byChannel)
                        Chip(
                          avatar: Icon(
                            switch (channel.channelCode) {
                              'whatsapp' => Icons.chat_outlined,
                              'telefono' => Icons.call_outlined,
                              _ => Icons.storefront_outlined,
                            },
                            size: 16,
                          ),
                          label: Text(
                            '${SaleChannel.fromCode(channel.channelCode).label}: '
                            '${Money.format(channel.totalCents)}',
                          ),
                        ),
                      for (final category in data.topCategories.take(4))
                        Chip(
                          avatar: const Icon(Icons.sell_outlined, size: 16),
                          label: Text(
                            '${category.category}: '
                            '${Money.format(category.totalCents)}',
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          // --------------------------------------------------------- cartera
          Text('Cartera de clientes', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            onChanged: (value) =>
                ref.read(customerSearchProvider.notifier).state = value,
            decoration: const InputDecoration(
              hintText: 'Buscar cliente…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          customers.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Center(child: Text('Error: $error')),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('Sin clientes registrados.',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: scheme.outline)),
                    ),
                  )
                : Column(
                    children: [
                      for (final customer in list)
                        _CustomerTile(customer: customer),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMayorista = customer.category == CustomerCategory.mayorista;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => showCustomerEditorSheet(context, existing: customer),
      leading: CircleAvatar(
        backgroundColor:
            isMayorista ? scheme.tertiaryContainer : scheme.primaryContainer,
        child: Text(
          customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
          style: TextStyle(
            color: isMayorista
                ? scheme.onTertiaryContainer
                : scheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(customer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          customer.category.label,
          if (customer.discountPercent > 0)
            '${customer.discountPercent % 1 == 0 ? customer.discountPercent.toInt() : customer.discountPercent}% desc.',
          if (customer.phone != null) customer.phone!,
          if (customer.lastPurchaseAt != null)
            'última ${timeAgo(customer.lastPurchaseAt!)}',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Money.format(customer.totalSpentCents),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            '${customer.purchaseCount} compras',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
