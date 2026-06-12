import '../../core/utils/result.dart';
import '../entities/insights.dart';
import '../entities/transaction.dart';

abstract class TransactionRepository {
  /// Persiste una transacción nueva de forma **atómica**:
  /// valida existencias, descuenta stock de las variantes vendidas
  /// (los servicios no tocan inventario), registra los movimientos,
  /// acumula `total_spent` del cliente si la venta nace completada y
  /// encola la operación en el Outbox. Todo o nada.
  Future<Result<Transaction>> processNew(Transaction transaction);

  /// Actualiza una transacción existente (cambios de estado de pedido).
  /// - [restock] devuelve existencias de las líneas de producto
  ///   (cancelaciones).
  /// - [creditCustomerStats] acumula el historial del cliente
  ///   (`total_spent`, compras) — usar al completar un pedido.
  /// También atómico + Outbox.
  Future<Result<Transaction>> update(
    Transaction transaction, {
    bool restock = false,
    bool creditCustomerStats = false,
  });

  Future<Transaction?> getById(String id);

  /// Pedidos (kind = pedido), opcionalmente filtrados por estado,
  /// del más reciente al más antiguo.
  Future<List<Transaction>> getOrders({OrderStatus? status});

  /// Transacciones creadas en el rango [from, to) — para métricas.
  Future<List<Transaction>> getByDateRange(DateTime from, DateTime to);

  Future<int> countOrders({required List<OrderStatus> statuses});

  // ------------------------------------------------ analítica local (SQL)

  /// Top de compradores por dinero cobrado (histórico completo).
  Future<List<TopBuyer>> getTopBuyers({int limit = 10});

  /// Ventas cobradas agrupadas por canal (mostrador/whatsapp/teléfono).
  Future<List<ChannelSales>> getSalesByChannel();

  /// Categorías más vendidas por importe.
  Future<List<CategorySales>> getTopCategories({int limit = 8});
}
