import '../../core/utils/id_generator.dart';
import '../entities/customer.dart';
import '../repositories/customer_repository.dart';
import 'import_catalog_usecase.dart' show ImportReport, SkippedRow;

/// Fila del archivo ya mapeada a campos de cliente.
class CustomerRowInput {
  const CustomerRowInput({
    required this.rowNumber,
    required this.name,
    this.phone = '',
    this.notes = '',
  });

  final int rowNumber;
  final String name;
  final String phone;
  final String notes;
}

/// Importa la cartera de clientes desde una tabla externa (Excel/CSV).
/// Deduplica primero por teléfono (solo dígitos) y después por nombre;
/// los existentes se completan con los datos nuevos sin duplicarse.
class ImportCustomersUseCase {
  ImportCustomersUseCase({
    required CustomerRepository customers,
    required IdGenerator idGenerator,
    DateTime Function()? now,
  })  : _customers = customers,
        _ids = idGenerator,
        _now = now ?? DateTime.now;

  final CustomerRepository _customers;
  final IdGenerator _ids;
  final DateTime Function() _now;

  Future<ImportReport> call(List<CustomerRowInput> rows) async {
    // Cartera completa para deduplicar (el límite alto cubre cualquier
    // negocio rural realista).
    final existing = await _customers.getRecent(1000000);
    final byPhone = <String, Customer>{
      for (final c in existing)
        if (_digits(c.phone).isNotEmpty) _digits(c.phone): c,
    };
    final byName = <String, Customer>{
      for (final c in existing) _normalize(c.name): c,
    };

    var created = 0;
    var updated = 0;
    final skipped = <SkippedRow>[];

    for (final row in rows) {
      final name = row.name.trim();
      if (name.isEmpty) {
        skipped.add(SkippedRow(rowNumber: row.rowNumber, reason: 'Sin nombre'));
        continue;
      }

      final phone = row.phone.trim();
      final notes = row.notes.trim();
      final phoneKey = _digits(phone);

      final found = (phoneKey.isNotEmpty ? byPhone[phoneKey] : null) ??
          byName[_normalize(name)];

      final Customer customer;
      final bool isNew;
      if (found == null) {
        isNew = true;
        customer = Customer(
          id: _ids.newId(),
          name: name,
          phone: phone.isEmpty ? null : phone,
          notes: notes.isEmpty ? null : notes,
          createdAt: _now(),
        );
      } else {
        isNew = false;
        customer = Customer(
          id: found.id,
          name: name,
          phone: phone.isEmpty ? found.phone : phone,
          notes: notes.isEmpty ? found.notes : notes,
          createdAt: found.createdAt,
        );
      }

      final result = await _customers.save(customer, isNew: isNew);
      result.fold(
        ok: (saved) {
          isNew ? created++ : updated++;
          if (phoneKey.isNotEmpty) byPhone[phoneKey] = saved;
          byName[_normalize(name)] = saved;
        },
        err: (failure) => skipped.add(
            SkippedRow(rowNumber: row.rowNumber, reason: failure.message)),
      );
    }

    return ImportReport(created: created, updated: updated, skipped: skipped);
  }

  String _digits(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\D'), '');

  String _normalize(String value) {
    var v = value.trim().toLowerCase();
    const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
    accents.forEach((from, to) => v = v.replaceAll(from, to));
    return v;
  }
}
