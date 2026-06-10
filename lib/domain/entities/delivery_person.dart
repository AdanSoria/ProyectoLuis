/// Repartidor al que se asignan los pedidos a domicilio.
class DeliveryPerson {
  const DeliveryPerson({
    required this.id,
    required this.name,
    this.phone,
    this.active = true,
  });

  /// UUID v4 generado en el cliente.
  final String id;
  final String name;
  final String? phone;
  final bool active;
}
