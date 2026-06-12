import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// Cierra el ciclo del pedido: `asignado -> completado`.
/// Registra cómo se cobró al entregar.
class CompleteOrderUseCase {
  CompleteOrderUseCase({
    required TransactionRepository transactions,
    DateTime Function()? now,
  })  : _transactions = transactions,
        _now = now ?? DateTime.now;

  final TransactionRepository _transactions;
  final DateTime Function() _now;

  Future<Result<Transaction>> call({
    required String orderId,
    PaymentMethod paymentMethod = PaymentMethod.efectivo,
  }) async {
    final order = await _transactions.getById(orderId);
    if (order == null) {
      return const Err(NotFoundFailure('El pedido ya no existe.'));
    }
    if (!order.status.canTransitionTo(OrderStatus.completado)) {
      return Err(InvalidTransitionFailure(
          'Un pedido ${order.status.label.toLowerCase()} no puede completarse; '
          'primero asígnalo a un repartidor.'));
    }
    // Al cobrar se acumula el historial del cliente (total_spent).
    return _transactions.update(
      order.completeWith(paymentMethod, order.totalCents, _now()),
      creditCustomerStats: true,
    );
  }
}
