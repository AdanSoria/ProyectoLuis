import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/db/app_database.dart';
import '../core/network/connectivity_service.dart';
import '../core/utils/id_generator.dart';
import '../data/remote/http_sync_gateway.dart';
import '../data/repositories/catalog_repository_impl.dart';
import '../data/repositories/customer_repository_impl.dart';
import '../data/repositories/delivery_repository_impl.dart';
import '../data/repositories/sync_queue_repository_impl.dart';
import '../data/repositories/transaction_repository_impl.dart';
import '../data/sync/sync_engine.dart';
import '../domain/entities/catalog_item.dart';
import '../domain/entities/customer.dart';
import '../domain/entities/delivery_person.dart';
import '../domain/entities/transaction.dart';
import '../domain/repositories/catalog_repository.dart';
import '../domain/repositories/customer_repository.dart';
import '../domain/repositories/delivery_repository.dart';
import '../domain/repositories/sync_gateway.dart';
import '../domain/repositories/sync_queue_repository.dart';
import '../domain/repositories/transaction_repository.dart';
import '../domain/usecases/assign_order_usecase.dart';
import '../domain/usecases/cancel_order_usecase.dart';
import '../domain/usecases/complete_order_usecase.dart';
import '../domain/usecases/get_sales_summary_usecase.dart';
import '../domain/usecases/process_transaction_usecase.dart';
import '../domain/usecases/sync_pending_operations_usecase.dart';
import 'state/cart_controller.dart';

/// Composition root: aquí (y solo aquí) la capa de presentación conoce
/// las implementaciones concretas de la capa de datos.

// ----------------------------------------------------------- infraestructura

/// Se inyecta con `overrideWithValue` en `main()` tras abrir la base.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('Inyectado en main()'),
);

final idGeneratorProvider =
    Provider<IdGenerator>((_) => const UuidV4Generator());

final connectivityServiceProvider =
    Provider<ConnectivityService>((_) => ConnectivityPlusService());

// ----------------------------------------------------------------- repos

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(idGeneratorProvider),
  ),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(idGeneratorProvider),
  ),
);

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(idGeneratorProvider),
  ),
);

final deliveryRepositoryProvider = Provider<DeliveryRepository>(
  (ref) => DeliveryRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(idGeneratorProvider),
  ),
);

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>(
  (ref) => SyncQueueRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final syncGatewayProvider = Provider<SyncGateway>(
  (_) => HttpSyncGateway(baseUrl: AppConfig.apiBaseUrl),
);

// ------------------------------------------------------------- casos de uso

final processTransactionUseCaseProvider = Provider(
  (ref) => ProcessTransactionUseCase(
    transactions: ref.watch(transactionRepositoryProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  ),
);

final assignOrderUseCaseProvider = Provider(
  (ref) =>
      AssignOrderUseCase(transactions: ref.watch(transactionRepositoryProvider)),
);

final completeOrderUseCaseProvider = Provider(
  (ref) => CompleteOrderUseCase(
      transactions: ref.watch(transactionRepositoryProvider)),
);

final cancelOrderUseCaseProvider = Provider(
  (ref) =>
      CancelOrderUseCase(transactions: ref.watch(transactionRepositoryProvider)),
);

final getSalesSummaryUseCaseProvider = Provider(
  (ref) => GetSalesSummaryUseCase(
      transactions: ref.watch(transactionRepositoryProvider)),
);

final syncPendingUseCaseProvider = Provider(
  (ref) => SyncPendingOperationsUseCase(
    queue: ref.watch(syncQueueRepositoryProvider),
    gateway: ref.watch(syncGatewayProvider),
  ),
);

// ------------------------------------------------------- motor de sincronía

final syncEngineProvider =
    StateNotifierProvider<SyncEngine, SyncEngineState>((ref) {
  return SyncEngine(
    syncPending: ref.watch(syncPendingUseCaseProvider),
    queue: ref.watch(syncQueueRepositoryProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    deviceId: ref.watch(appDatabaseProvider).deviceId,
  );
});

// ------------------------------------------------------- estado de pantalla

final cartProvider = StateNotifierProvider<CartController, CartState>(
  (ref) => CartController(ref.watch(appDatabaseProvider)),
);

final catalogListProvider = FutureProvider<List<CatalogItem>>(
  (ref) => ref.watch(catalogRepositoryProvider).getAll(),
);

final catalogSearchProvider = StateProvider<String>((_) => '');

final categoryFilterProvider = StateProvider<String?>((_) => null);

/// Categorías derivadas del catálogo (para los chips de filtro).
final categoriesProvider = Provider<AsyncValue<List<String>>>((ref) {
  return ref.watch(catalogListProvider).whenData((items) {
    final categories = items.map((i) => i.category).toSet().toList()..sort();
    return categories;
  });
});

/// Catálogo filtrado por búsqueda + categoría (cero fricción al teclear).
final filteredCatalogProvider = Provider<AsyncValue<List<CatalogItem>>>((ref) {
  final query = ref.watch(catalogSearchProvider).trim().toLowerCase();
  final category = ref.watch(categoryFilterProvider);
  return ref.watch(catalogListProvider).whenData((items) {
    return [
      for (final item in items)
        if ((category == null || item.category == category) &&
            (query.isEmpty || item.name.toLowerCase().contains(query)))
          item,
    ];
  });
});

final ordersProvider = FutureProvider.family<List<Transaction>, OrderStatus?>(
  (ref, status) =>
      ref.watch(transactionRepositoryProvider).getOrders(status: status),
);

final pendingOrdersCountProvider = FutureProvider<int>(
  (ref) => ref.watch(transactionRepositoryProvider).countOrders(
    statuses: const [OrderStatus.pendiente, OrderStatus.asignado],
  ),
);

final recentCustomersProvider = FutureProvider<List<Customer>>(
  (ref) => ref.watch(customerRepositoryProvider).getRecent(8),
);

final deliveryPeopleProvider = FutureProvider<List<DeliveryPerson>>(
  (ref) => ref.watch(deliveryRepositoryProvider).getActive(),
);

final salesSummaryProvider = FutureProvider(
  (ref) => ref.watch(getSalesSummaryUseCaseProvider).call(),
);

/// Invalida todas las vistas derivadas de datos tras una mutación
/// (venta, cambio de estado, ajuste de stock) y refresca el contador
/// del Outbox. Llamar después de cada caso de uso exitoso.
void refreshAfterMutation(WidgetRef ref) {
  ref.invalidate(catalogListProvider);
  ref.invalidate(ordersProvider);
  ref.invalidate(pendingOrdersCountProvider);
  ref.invalidate(recentCustomersProvider);
  ref.invalidate(salesSummaryProvider);
  final engine = ref.read(syncEngineProvider.notifier);
  Future<void>.microtask(() async {
    await engine.refreshPending();
    await engine.syncNow();
  });
}
