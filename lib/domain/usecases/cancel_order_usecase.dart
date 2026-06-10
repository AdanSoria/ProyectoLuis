import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// Cancela un pedido no entregado y **devuelve las existencias** de las
/// líneas de producto al inventario (los servicios no se devuelven).
class CancelOrderUseCase {
  CancelOrderUseCase({
    required TransactionRepository transactions,
    DateTime Function()? now,
  })  : _transactions = transactions,
        _now = now ?? DateTime.now;

  final TransactionRepository _transactions;
  final DateTime Function() _now;

  Future<Result<Transaction>> call({required String orderId}) async {
    final order = await _transactions.getById(orderId);
    if (order == null) {
      return const Err(NotFoundFailure('El pedido ya no existe.'));
    }
    if (!order.status.canTransitionTo(OrderStatus.cancelado)) {
      return Err(InvalidTransitionFailure(
          'Un pedido ${order.status.label.toLowerCase()} ya no puede cancelarse.'));
    }
    return _transactions.update(order.cancelled(_now()), restock: true);
  }
}
