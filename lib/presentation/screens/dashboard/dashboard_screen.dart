import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../data/sync/sync_engine.dart';
import '../../providers.dart';
import 'export_dialog.dart';

/// Resumen del día: flujo de caja (ventas y utilidad neta), pedidos
/// vivos, top de artículos y salud de la sincronización.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(salesSummaryProvider);
    final sync = ref.watch(syncEngineProvider);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(salesSummaryProvider),
      child: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (data) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text('Hoy', style: textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                  tooltip: 'Actualizar',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(salesSummaryProvider),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  icon: Icons.attach_money,
                  label: 'Ventas cobradas',
                  value: Money.format(data.totalSalesCents),
                  caption: '${data.ticketCount} tickets · promedio '
                      '${Money.format(data.averageTicketCents)}',
                ),
                _MetricCard(
                  icon: Icons.trending_up,
                  label: 'Utilidad neta',
                  value: Money.format(data.netProfitCents),
                  caption: data.totalSalesCents == 0
                      ? '—'
                      : 'margen ${(data.netProfitCents * 100 / data.totalSalesCents).toStringAsFixed(1)}%',
                ),
                _MetricCard(
                  icon: Icons.local_shipping_outlined,
                  label: 'Pedidos por atender',
                  value: '${data.pendingOrders}',
                  caption: 'pendientes + asignados',
                ),
                _MetricCard(
                  icon: switch (sync.phase) {
                    SyncPhase.disabled => Icons.cloud_off_outlined,
                    SyncPhase.offline => Icons.wifi_off_outlined,
                    SyncPhase.syncing => Icons.cloud_sync_outlined,
                    SyncPhase.error => Icons.sync_problem_outlined,
                    SyncPhase.idle => Icons.cloud_done_outlined,
                  },
                  label: 'Por sincronizar',
                  value: '${sync.pendingCount}',
                  caption: switch (sync.phase) {
                    SyncPhase.disabled => 'modo local (sin servidor)',
                    SyncPhase.offline => 'sin conexión',
                    SyncPhase.syncing => 'enviando…',
                    SyncPhase.error => sync.message ?? 'error de envío',
                    SyncPhase.idle => 'al día',
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () =>
                      ref.read(syncEngineProvider.notifier).syncNow(),
                  icon: const Icon(Icons.sync),
                  label: const Text('Sincronizar ahora'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showExportDialog(context),
                  icon: const Icon(Icons.table_view),
                  label: const Text('Exportar a Excel'),
                ),
                if (sync.phase == SyncPhase.error)
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(syncEngineProvider.notifier).retryErrored(),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reintentar fallidos'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Más vendidos hoy', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            if (data.topItems.isEmpty)
              Text(
                'Aún no hay ventas registradas hoy.',
                style: textTheme.bodyMedium?.copyWith(color: scheme.outline),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final (index, item) in data.topItems.indexed)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(item.name),
                        subtitle: Text(
                          item.quantity % 1 == 0
                              ? '${item.quantity.toInt()} vendidos'
                              : '${item.quantity.toStringAsFixed(2)} vendidos',
                        ),
                        trailing: Text(
                          Money.format(item.totalCents),
                          style: textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        style: textTheme.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                caption,
                style: textTheme.labelSmall?.copyWith(color: scheme.outline),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
