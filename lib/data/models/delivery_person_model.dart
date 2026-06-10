import '../../domain/entities/delivery_person.dart';

class DeliveryPersonModel {
  DeliveryPersonModel._();

  static Map<String, Object?> toRow(DeliveryPerson p) => {
        'id': p.id,
        'nombre': p.name,
        'telefono': p.phone,
        'activo': p.active ? 1 : 0,
      };

  static DeliveryPerson fromRow(Map<String, Object?> row) => DeliveryPerson(
        id: row['id'] as String,
        name: row['nombre'] as String,
        phone: row['telefono'] as String?,
        active: (row['activo'] as num? ?? 1) == 1,
      );

  static Map<String, dynamic> toSyncJson(DeliveryPerson p) => toRow(p);
}
