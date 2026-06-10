import '../../core/errors/failures.dart';
import '../../core/utils/folio.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/result.dart';
import '../entities/cart_line.dart';
import '../entities/customer.dart';
import '../entities/delivery_person.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// Entrada del caso de uso. La UI solo arma esto desde el carrito;
/// toda la regla de negocio vive aquí abajo.
class ProcessTransactionInput {
  const ProcessTransactionInput({
    required this.lines,
    required this.kind,
    this.channel = SaleChannel.mostrador,
    this.paymentMethod = PaymentMethod.efectivo,
    this.amountPaidCents = 0,
    this.deductionsCents = 0,
    this.customer,
    this.customerName,
    this.customerPhone,
    this.deliveryPerson,
    this.notes,
  });

  final List<CartLine> lines;
  final TransactionKind kind;
  final SaleChannel channel;

  /// Solo aplica a venta de mostrador (los pedidos quedan `por_cobrar`).
  final PaymentMethod paymentMethod;
  final int amountPaidCents;

  /// Descuentos/rebajas del ticket, en centavos.
  final int deductionsCents;

  /// Cliente existente seleccionado por chip (opcional)…
  final Customer? customer;

  /// …o captura rápida de nombre/teléfono para pedidos nuevos.
  final String? customerName;
  final String? customerPhone;

  /// Si viene, el pedido nace directamente `asignado` (flujo de 3 pasos).
  final DeliveryPerson? deliveryPerson;

  final String? notes;
}

/// Caso de uso principal: procesa una venta de mostrador o registra un
/// pedido de reparto.
///
/// Responsabilidades:
/// 1. Validar el carrito y los datos mínimos según el tipo de operación.
/// 2. Construir la entidad [Transaction] con UUID v4 de cliente, folio,
///    snapshot de precios y estado inicial correcto.
/// 3. Delegar al repositorio el guardado local atómico, que descuenta
///    stock de productos (no de servicios) y **encola la operación en la
///    Cola de Sincronización (Outbox) en la misma transacción**.
class ProcessTransactionUseCase {
  ProcessTransactionUseCase({
    required TransactionRepository transactions,
    required IdGenerator idGenerator,
    DateTime Function()? now,
  })  : _transactions = transactions,
        _ids = idGenerator,
        _now = now ?? DateTime.now;

  final TransactionRepository _transactions;
  final IdGenerator _ids;
  final DateTime Function() _now;

  Future<Result<Transaction>> call(ProcessTransactionInput input) async {
    // ---- 1. Validaciones de dominio -------------------------------------
    if (input.lines.isEmpty) {
      return const Err(ValidationFailure('El carrito está vacío.'));
    }
    for (final line in input.lines) {
      if (line.quantity <= 0) {
        return Err(ValidationFailure(
            'Cantidad inválida para "${line.item.name}".'));
      }
    }
    if (input.deductionsCents < 0) {
      return const Err(ValidationFailure('El descuento no puede ser negativo.'));
    }

    final subtotal =
        input.lines.fold<int>(0, (sum, l) => sum + l.totalCents);
    final total = subtotal - input.deductionsCents;
    if (total < 0) {
      return const Err(
          ValidationFailure('El descuento supera el importe del ticket.'));
    }

    final isOrder = input.kind == TransactionKind.pedido;

    final customerName =
        (input.customer?.name ?? input.customerName)?.trim() ?? '';
    final customerPhone =
        (input.customer?.phone ?? input.customerPhone)?.trim();
    if (isOrder && customerName.isEmpty) {
      return const Err(ValidationFailure(
          'Un pedido necesita al menos el nombre del cliente.'));
    }

    if (!isOrder &&
        input.paymentMethod == PaymentMethod.efectivo &&
        input.amountPaidCents < total) {
      return const Err(
          ValidationFailure('El monto recibido no cubre el total.'));
    }

    // ---- 2. Construcción de la entidad ----------------------------------
    final id = _ids.newId(); // UUID v4 generado en el cliente
    final now = _now();

    final lines = [
      for (final cartLine in input.lines)
        TransactionLine(
          id: _ids.newId(),
          itemId: cartLine.item.id,
          itemName: cartLine.item.name,
          isService: cartLine.item.isService,
          quantity: cartLine.quantity,
          unitPriceCents: cartLine.item.salePriceCents, // precio_venta
          unitCostCents: cartLine.item.costPriceCents, // precio_costo
        ),
    ];

    // Estado inicial: mostrador nace completado; un pedido nace asignado
    // si ya trae repartidor, o pendiente si se asignará después.
    final OrderStatus status;
    if (!isOrder) {
      status = OrderStatus.completado;
    } else if (input.deliveryPerson != null) {
      status = OrderStatus.asignado;
    } else {
      status = OrderStatus.pendiente;
    }

    final transaction = Transaction(
      id: id,
      folio: Folio.fromUuid(id, now),
      kind: input.kind,
      channel: input.channel,
      status: status,
      lines: lines,
      deductionsCents: input.deductionsCents,
      paymentMethod:
          isOrder ? PaymentMethod.porCobrar : input.paymentMethod,
      amountPaidCents: isOrder
          ? 0
          : (input.paymentMethod == PaymentMethod.efectivo
              ? input.amountPaidCents
              : total),
      customerId: input.customer?.id,
      customerName: customerName.isEmpty ? null : customerName,
      customerPhone:
          (customerPhone == null || customerPhone.isEmpty) ? null : customerPhone,
      deliveryPersonId: input.deliveryPerson?.id,
      deliveryPersonName: input.deliveryPerson?.name,
      notes: input.notes?.trim().isEmpty ?? true ? null : input.notes!.trim(),
      createdAt: now,
      updatedAt: now,
    );

    // ---- 3. Guardado local atómico + encolado en el Outbox ---------------
    return _transactions.processNew(transaction);
  }
}
