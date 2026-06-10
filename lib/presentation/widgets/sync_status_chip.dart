import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_engine.dart';
import '../providers.dart';

/// Chip permanente en la barra superior: muestra el estado del Outbox
/// sin estorbar. Tocarlo fuerza un ciclo de sincronización.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncEngineProvider);
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, String label, Color color) = switch (sync.phase) {
      SyncPhase.disabled => (
          Icons.cloud_off_outlined,
          sync.pendingCount == 0
              ? 'Local'
              : 'Local · ${sync.pendingCount} en cola',
          scheme.outline,
        ),
      SyncPhase.offline => (
          Icons.wifi_off_outlined,
          'Sin conexión · ${sync.pendingCount}',
          scheme.error,
        ),
      SyncPhase.syncing => (
          Icons.cloud_sync_outlined,
          'Sincronizando…',
          scheme.primary,
        ),
      SyncPhase.error => (
          Icons.sync_problem_outlined,
          'Error · ${sync.pendingCount}',
          scheme.error,
        ),
      SyncPhase.idle => sync.pendingCount == 0
          ? (Icons.cloud_done_outlined, 'Al día', scheme.primary)
          : (
              Icons.cloud_upload_outlined,
              '${sync.pendingCount} por enviar',
              scheme.tertiary,
            ),
    };

    return Tooltip(
      message: sync.message ?? 'Tocar para sincronizar ahora',
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
        onPressed: () => ref.read(syncEngineProvider.notifier).syncNow(),
      ),
    );
  }
}
