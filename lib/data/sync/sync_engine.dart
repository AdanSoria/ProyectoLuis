import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/utils/result.dart';
import '../../domain/repositories/sync_queue_repository.dart';
import '../../domain/usecases/sync_pending_operations_usecase.dart';

enum SyncPhase {
  /// Sin servidor configurado: la app trabaja 100% local y acumula cola.
  disabled,
  offline,
  idle,
  syncing,
  error,
}

class SyncEngineState {
  const SyncEngineState({
    this.phase = SyncPhase.idle,
    this.pendingCount = 0,
    this.lastSyncAt,
    this.message,
  });

  final SyncPhase phase;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final String? message;

  SyncEngineState copyWith({
    SyncPhase? phase,
    int? pendingCount,
    DateTime? lastSyncAt,
    String? message,
  }) =>
      SyncEngineState(
        phase: phase ?? this.phase,
        pendingCount: pendingCount ?? this.pendingCount,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        message: message,
      );
}

/// Orquestador de la sincronización **silenciosa**:
/// - al recuperar conexión (stream de conectividad) dispara un ciclo;
/// - cada [AppConfig.syncInterval] reintenta en segundo plano;
/// - drena la cola por lotes hasta vaciarla o agotar reintentos.
///
/// La UI solo observa [SyncEngineState] para pintar el chip de estado.
class SyncEngine extends StateNotifier<SyncEngineState> {
  SyncEngine({
    required SyncPendingOperationsUseCase syncPending,
    required SyncQueueRepository queue,
    required ConnectivityService connectivity,
    required String deviceId,
    String apiBaseUrl = AppConfig.apiBaseUrl,
  })  : _syncPending = syncPending,
        _queue = queue,
        _connectivity = connectivity,
        _deviceId = deviceId,
        _serverConfigured = apiBaseUrl.isNotEmpty,
        super(const SyncEngineState());

  final SyncPendingOperationsUseCase _syncPending;
  final SyncQueueRepository _queue;
  final ConnectivityService _connectivity;
  final String _deviceId;
  final bool _serverConfigured;

  StreamSubscription<bool>? _connectivitySub;
  Timer? _timer;
  bool _started = false;
  bool _running = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Lo que quedó "enviando" en un cierre abrupto vuelve a la cola.
    await _queue.resetInFlight();
    await refreshPending();

    _connectivitySub = _connectivity.onStatusChange.listen((online) {
      if (online) {
        unawaited(syncNow());
      } else {
        state = state.copyWith(phase: SyncPhase.offline);
      }
    });

    _timer = Timer.periodic(AppConfig.syncInterval, (_) {
      unawaited(syncNow());
    });

    unawaited(syncNow());
  }

  Future<void> refreshPending() async {
    final count = await _queue.pendingCount();
    if (!mounted) return;
    state = state.copyWith(pendingCount: count);
  }

  /// Reencola manualmente las operaciones marcadas en error.
  Future<void> retryErrored() async {
    await _queue.retryErrored();
    await syncNow();
  }

  Future<void> syncNow() async {
    if (_running) return;
    _running = true;
    try {
      if (!_serverConfigured) {
        final count = await _queue.pendingCount();
        if (!mounted) return;
        state = state.copyWith(
          phase: SyncPhase.disabled,
          pendingCount: count,
          message: 'Modo local: sin servidor configurado.',
        );
        return;
      }

      if (!await _connectivity.hasConnection()) {
        final count = await _queue.pendingCount();
        if (!mounted) return;
        state = state.copyWith(phase: SyncPhase.offline, pendingCount: count);
        return;
      }

      if (!mounted) return;
      state = state.copyWith(phase: SyncPhase.syncing);

      // Drena la cola por lotes. Las operaciones que fallan reciben
      // backoff, así que takeBatch deja de devolverlas en este ciclo
      // y el while termina solo.
      while (true) {
        final result = await _syncPending(deviceId: _deviceId);

        if (result case Err(:final failure)) {
          if (!mounted) return;
          state = state.copyWith(
            phase: SyncPhase.error,
            pendingCount: await _queue.pendingCount(),
            message: failure.message,
          );
          return;
        }

        final report = (result as Ok<SyncRunReport>).value;
        if (!report.hadWork || report.remaining == 0) {
          if (!mounted) return;
          state = state.copyWith(
            phase: SyncPhase.idle,
            pendingCount: report.remaining,
            lastSyncAt: DateTime.now(),
          );
          return;
        }
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_connectivitySub?.cancel());
    super.dispose();
  }
}
