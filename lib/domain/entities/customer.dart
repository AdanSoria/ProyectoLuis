/// Cliente del mini-CRM. Captura mínima: con nombre o teléfono basta
/// para registrar un pedido (fricción cero).
class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.notes,
    required this.createdAt,
  });

  /// UUID v4 generado en el cliente.
  final String id;
  final String name;
  final String? phone;
  final String? notes;
  final DateTime createdAt;
}
