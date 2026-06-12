import 'dart:math' as math;

import 'delivery_person.dart';

/// Tipo de transacción.
enum TransactionKind {
  /// Venta directa en mostrador: nace y muere `completado`.
  ventaMostrador('venta_mostrador', 'Venta de mostrador'),

  /// Pedido multicanal (WhatsApp/teléfono) que pasa por la máquina
  /// de estados de reparto.
  pedido('pedido', 'Pedido');

  const TransactionKind(this.code, this.label);
  final String code;
  final String label;

  static TransactionKind fromCode(String code) =>
      values.firstWhere((v) => v.code == code);
}

/// Canal por el que entró la transacción.
enum SaleChannel {
  mostrador('mostrador', 'Mostrador'),
  whatsapp('whatsapp', 'WhatsApp'),
  telefono('telefono', 'Teléfono');

  const SaleChannel(this.code, this.label);
  final String code;
  final String label;

  static SaleChannel fromCode(String code) =>
      values.firstWhere((v) => v.code == code);
}

enum PaymentMethod {
  efectivo('efectivo', 'Efectivo'),
  tarjeta('tarjeta', 'Tarjeta'),
  transferencia('transferencia', 'Transferencia'),

  /// Pedido aún no cobrado (se cobra al entregar).
  porCobrar('por_cobrar', 'Por cobrar');

  const PaymentMethod(this.code, this.label);
  final String code;
  final String label;

  static PaymentMethod fromCode(String code) =>
      values.firstWhere((v) => v.code == code);
}

/// Máquina de estados del flujo de pedidos:
///
/// `pendiente` -> `asignado` -> `completado`
///      \------------\--------> `cancelado`
///
/// (Una venta de mostrador nace directamente en `completado`.)
enum OrderStatus {
  pendiente('pendiente', 'Pendiente'),
  asignado('asignado', 'Asignado a repartidor'),
  completado('completado', 'Completado'),
  cancelado('cancelado', 'Cancelado');

  const OrderStatus(this.code, this.label);
  final String code;
  final String label;

  static OrderStatus fromCode(String code) =>
      values.firstWhere((v) => v.code == code);

  /// Transiciones válidas. `asignado -> asignado` permite reasignar
  /// el pedido a otro repartidor.
  bool canTransitionTo(OrderStatus next) => switch ((this, next)) {
        (OrderStatus.pendiente, OrderStatus.asignado) => true,
        (OrderStatus.pendiente, OrderStatus.cancelado) => true,
        (OrderStatus.asignado, OrderStatus.asignado) => true,
        (OrderStatus.asignado, OrderStatus.completado) => true,
        (OrderStatus.asignado, OrderStatus.cancelado) => true,
        _ => false,
      };

  bool get isFinal => this == completado || this == cancelado;
}

/// Línea inmutable de una transacción. Congela nombre, variante y precios
/// del artículo al momento de la venta (snapshot), de modo que cambios
/// futuros del catálogo no alteren la historia financiera.
class TransactionLine {
  const TransactionLine({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.isService,
    required this.quantity,
    required this.unitPriceCents,
    required this.unitCostCents,
    this.variantId,
    this.variantName,
    int? listUnitPriceCents,
  }) : listUnitPriceCents = listUnitPriceCents ?? unitPriceCents;

  /// UUID v4 generado en el cliente.
  final String id;
  final String itemId;
  final String itemName;
  final bool isService;
  final double quantity;

  /// `precio_venta` unitario EFECTIVO (puede venir de regateo), centavos.
  final int unitPriceCents;

  /// `precio_costo` unitario congelado, en centavos.
  final int unitCostCents;

  /// Variante vendida (== [itemId] para la variante default/servicios).
  final String? variantId;
  final String? variantName;

  /// `precio_lista`: el precio antes del regateo, para auditoría.
  final int listUnitPriceCents;

  /// Hubo sobreescritura manual de precio en esta línea.
  bool get wasNegotiated => unitPriceCents != listUnitPriceCents;

  /// Importe de la línea (venta).
  int get totalCents => (unitPriceCents * quantity).round();

  /// Costo de la línea.
  int get totalCostCents => (unitCostCents * quantity).round();
}

/// Transacción de negocio: venta de mostrador o pedido a domicilio.
///
/// Las métricas financieras son derivadas (nunca capturadas):
/// - `subtotal`      = Σ importes de línea
/// - `total`         = subtotal - deducciones (descuentos/rebajas)
/// - `costo total`   = Σ costos de línea
/// - `utilidad_neta` = total - costo total
class Transaction {
  const Transaction({
    required this.id,
    required this.folio,
    required this.kind,
    required this.channel,
    required this.status,
    required this.lines,
    this.deductionsCents = 0,
    this.paymentMethod = PaymentMethod.efectivo,
    this.amountPaidCents = 0,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.deliveryPersonId,
    this.deliveryPersonName,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// UUID v4 generado en el cliente (evita colisiones al sincronizar).
  final String id;

  /// Folio corto legible derivado del UUID (para tickets y teléfono).
  final String folio;

  final TransactionKind kind;
  final SaleChannel channel;
  final OrderStatus status;
  final List<TransactionLine> lines;

  /// Deducciones aplicadas al ticket (descuentos, rebajas), en centavos.
  final int deductionsCents;

  final PaymentMethod paymentMethod;

  /// Monto recibido del cliente, en centavos (para calcular cambio).
  final int amountPaidCents;

  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryPersonId;
  final String? deliveryPersonName;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ------------------------------------------------- métricas financieras

  int get subtotalCents => lines.fold(0, (sum, l) => sum + l.totalCents);

  int get totalCents => math.max(0, subtotalCents - deductionsCents);

  /// `precio_costo` total de la mercancía/servicios vendidos.
  int get costTotalCents => lines.fold(0, (sum, l) => sum + l.totalCostCents);

  /// `utilidad_neta` = flujo real que deja la operación.
  int get netProfitCents => totalCents - costTotalCents;

  /// Cambio a devolver cuando se cobra en efectivo.
  int get changeCents => math.max(0, amountPaidCents - totalCents);

  bool get isOrder => kind == TransactionKind.pedido;

  double get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);

  // ------------------------------------------- transiciones de la máquina

  /// Asigna (o reasigna) el pedido a un repartidor.
  Transaction assignTo(DeliveryPerson person, DateTime now) => _copy(
        status: OrderStatus.asignado,
        deliveryPersonId: person.id,
        deliveryPersonName: person.name,
        updatedAt: now,
      );

  /// Marca el pedido como entregado y cobrado.
  Transaction completeWith(
          PaymentMethod method, int amountPaidCents, DateTime now) =>
      _copy(
        status: OrderStatus.completado,
        paymentMethod: method,
        amountPaidCents: amountPaidCents,
        updatedAt: now,
      );

  Transaction cancelled(DateTime now) =>
      _copy(status: OrderStatus.cancelado, updatedAt: now);

  Transaction _copy({
    OrderStatus? status,
    PaymentMethod? paymentMethod,
    int? amountPaidCents,
    String? deliveryPersonId,
    String? deliveryPersonName,
    DateTime? updatedAt,
  }) =>
      Transaction(
        id: id,
        folio: folio,
        kind: kind,
        channel: channel,
        status: status ?? this.status,
        lines: lines,
        deductionsCents: deductionsCents,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        amountPaidCents: amountPaidCents ?? this.amountPaidCents,
        customerId: customerId,
        customerName: customerName,
        customerPhone: customerPhone,
        deliveryPersonId: deliveryPersonId ?? this.deliveryPersonId,
        deliveryPersonName: deliveryPersonName ?? this.deliveryPersonName,
        notes: notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
