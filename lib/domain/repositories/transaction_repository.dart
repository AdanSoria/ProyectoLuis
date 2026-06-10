import '../../core/utils/result.dart';
import '../entities/transaction.dart';

abstract class TransactionRepository {
  /// Persiste una transacción nueva de forma **atómica**:
  /// valida existencias, descuenta stock de las líneas de producto
  /// (los servicios no tocan inventario), registra los movimientos y
  /// encola la operación en el Outbox. Todo o nada.
  Future<Result<Transaction>> processNew(Transaction transaction);

  /// Actualiza una transacción existente (cambios de estado de pedido).
  /// Con [restock] devuelve las existencias de las líneas de producto
  /// (cancelaciones), también de forma atómica + Outbox.
  Future<Result<Transaction>> update(
    Transaction transaction, {
    bool restock = false,
  });

  Future<Transaction?> getById(String id);

  /// Pedidos (kind = pedido), opcionalmente filtrados por estado,
  /// del más reciente al más antiguo.
  Future<List<Transaction>> getOrders({OrderStatus? status});

  /// Transacciones creadas en el rango [from, to) — para métricas.
  Future<List<Transaction>> getByDateRange(DateTime from, DateTime to);

  Future<int> countOrders({required List<OrderStatus> statuses});
}
