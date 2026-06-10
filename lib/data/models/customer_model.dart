import '../../domain/entities/customer.dart';

class CustomerModel {
  CustomerModel._();

  static Map<String, Object?> toRow(Customer c) => {
        'id': c.id,
        'nombre': c.name,
        'telefono': c.phone,
        'notas': c.notes,
        'creado_en': c.createdAt.toIso8601String(),
      };

  static Customer fromRow(Map<String, Object?> row) => Customer(
        id: row['id'] as String,
        name: row['nombre'] as String,
        phone: row['telefono'] as String?,
        notes: row['notas'] as String?,
        createdAt: DateTime.parse(row['creado_en'] as String),
      );

  static Map<String, dynamic> toSyncJson(Customer c) => toRow(c);
}
