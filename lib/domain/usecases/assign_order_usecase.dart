import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../entities/delivery_person.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// Asigna (o reasigna) un pedido a un repartidor:
/// `pendiente -> asignado` (o `asignado -> asignado`).
class AssignOrderUseCase {
  AssignOrderUseCase({
    required TransactionRepository transactions,
    DateTime Function()? now,
  })  : _transactions = transactions,
        _now = now ?? DateTime.now;

  final TransactionRepository _transactions;
  final DateTime Function() _now;

  Future<Result<Transaction>> call({
    required String orderId,
    required DeliveryPerson deliveryPerson,
  }) async {
    final order = await _transactions.getById(orderId);
    if (order == null) {
      return const Err(NotFoundFailure('El pedido ya no existe.'));
    }
    if (!order.isOrder) {
      return const Err(
          ValidationFailure('Solo los pedidos pueden asignarse a reparto.'));
    }
    if (!order.status.canTransitionTo(OrderStatus.asignado)) {
      return Err(InvalidTransitionFailure(
          'No se puede asignar un pedido ${order.status.label.toLowerCase()}.'));
    }
    return _transactions.update(order.assignTo(deliveryPerson, _now()));
  }
}
