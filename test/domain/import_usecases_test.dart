import 'package:agropos/core/utils/id_generator.dart';
import 'package:agropos/core/utils/result.dart';
import 'package:agropos/domain/entities/catalog_item.dart';
import 'package:agropos/domain/entities/customer.dart';
import 'package:agropos/domain/repositories/catalog_repository.dart';
import 'package:agropos/domain/repositories/customer_repository.dart';
import 'package:agropos/domain/usecases/import_catalog_usecase.dart';
import 'package:agropos/domain/usecases/import_customers_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCatalogRepo implements CatalogRepository {
  final items = <CatalogItem>[];

  @override
  Future<List<CatalogItem>> getAll({bool includeInactive = false}) async =>
      [for (final i in items) if (includeInactive || i.active) i];

  @override
  Future<CatalogItem?> getById(String id) async =>
      items.where((i) => i.id == id).firstOrNull;

  @override
  Future<Result<CatalogItem>> save(CatalogItem item,
      {required bool isNew}) async {
    items.removeWhere((i) => i.id == item.id);
    items.add(item);
    return Ok(item);
  }

  @override
  Future<Result<void>> adjustStock(
          {required String productId,
          required double delta,
          required String reason}) async =>
      const Ok(null);
}

class _FakeCustomerRepo implements CustomerRepository {
  final customers = <Customer>[];

  @override
  Future<List<Customer>> getRecent(int limit) async =>
      customers.take(limit).toList();

  @override
  Future<List<Customer>> search(String query) async => customers;

  @override
  Future<Result<Customer>> save(Customer customer,
      {required bool isNew}) async {
    customers.removeWhere((c) => c.id == customer.id);
    customers.add(customer);
    return Ok(customer);
  }
}

class _SequentialIds implements IdGenerator {
  int _n = 0;

  @override
  String newId() => 'uuid-${++_n}';
}

void main() {
  final t0 = DateTime.utc(2026, 6, 10);

  group('ImportCatalogUseCase', () {
    late _FakeCatalogRepo repo;
    late ImportCatalogUseCase useCase;

    setUp(() {
      repo = _FakeCatalogRepo();
      useCase = ImportCatalogUseCase(
        catalog: repo,
        idGenerator: _SequentialIds(),
        now: () => t0,
      );
    });

    test('crea productos y servicios nuevos con UUID', () async {
      final report = await useCase([
        const CatalogRowInput(
          rowNumber: 2,
          name: 'Maíz híbrido 20 kg',
          salePriceCents: 175000,
          costPriceCents: 145000,
          stock: 24,
          category: 'Semillas',
          unit: 'bulto',
        ),
        const CatalogRowInput(
          rowNumber: 3,
          name: 'Consulta veterinaria',
          salePriceCents: 25000,
          isService: true,
        ),
      ]);

      expect(report.created, 2);
      expect(report.updated, 0);
      expect(report.skipped, isEmpty);

      final product = repo.items.first as Product;
      expect(product.id, 'uuid-1');
      expect(product.stock, 24);
      expect(product.unit, 'bulto');

      final service = repo.items.last;
      expect(service, isA<Service>());
      expect(service.category, 'General'); // sin categoría → General
    });

    test('actualiza por nombre (sin duplicar) y conserva lo no mapeado',
        () async {
      repo.items.add(Product(
        id: 'p1',
        name: 'Urea 46% 50 kg',
        category: 'Fertilizantes',
        costPriceCents: 69000,
        salePriceCents: 84000,
        unit: 'bulto',
        stock: 32,
        active: false, // estaba oculto: la importación lo revive
        createdAt: t0,
        updatedAt: t0,
      ));

      final report = await useCase([
        const CatalogRowInput(
          rowNumber: 2,
          name: '  UREA 46% 50 KG ', // mismo nombre, otra forma
          salePriceCents: 89000,
          // sin costo ni stock mapeados → se conservan los actuales
        ),
      ]);

      expect(report.created, 0);
      expect(report.updated, 1);
      expect(repo.items, hasLength(1)); // no duplicó

      final updated = repo.items.single as Product;
      expect(updated.id, 'p1'); // mismo registro
      expect(updated.salePriceCents, 89000); // el archivo manda
      expect(updated.costPriceCents, 69000); // conservado
      expect(updated.stock, 32); // conservado
      expect(updated.active, isTrue); // reactivado
    });

    test('omite filas inválidas con motivo y número de fila', () async {
      final report = await useCase([
        const CatalogRowInput(rowNumber: 2, name: '', salePriceCents: 100),
        const CatalogRowInput(
            rowNumber: 3, name: 'Sin precio', salePriceCents: 0),
        const CatalogRowInput(
            rowNumber: 4, name: 'Válido', salePriceCents: 5000),
      ]);

      expect(report.created, 1);
      expect(report.skipped, hasLength(2));
      expect(report.skipped.first.rowNumber, 2);
      expect(report.skipped.first.reason, 'Sin nombre');
      expect(report.skipped.last.rowNumber, 3);
      expect(report.skipped.last.reason, contains('Precio'));
    });
  });

  group('ImportCustomersUseCase', () {
    late _FakeCustomerRepo repo;
    late ImportCustomersUseCase useCase;

    setUp(() {
      repo = _FakeCustomerRepo();
      useCase = ImportCustomersUseCase(
        customers: repo,
        idGenerator: _SequentialIds(),
        now: () => t0,
      );
    });

    test('crea nuevos y deduplica por teléfono aunque cambie el nombre',
        () async {
      repo.customers.add(Customer(
        id: 'c1',
        name: 'Rancho El Mezquite',
        phone: '555-000-0001',
        createdAt: t0,
      ));

      final report = await useCase([
        // Mismo teléfono con otro formato → actualiza, no duplica.
        const CustomerRowInput(
            rowNumber: 2, name: 'Rancho Mezquite SA', phone: '5550000001'),
        const CustomerRowInput(
            rowNumber: 3, name: 'Granja Nueva', phone: '5559998888'),
        const CustomerRowInput(rowNumber: 4, name: ''),
      ]);

      expect(report.updated, 1);
      expect(report.created, 1);
      expect(report.skipped, hasLength(1));
      expect(repo.customers, hasLength(2));

      final merged = repo.customers.firstWhere((c) => c.id == 'c1');
      expect(merged.name, 'Rancho Mezquite SA');
    });

    test('deduplica por nombre cuando no hay teléfono', () async {
      repo.customers.add(Customer(
        id: 'c1',
        name: 'Granja Santa Fe',
        createdAt: t0,
      ));

      final report = await useCase([
        const CustomerRowInput(
            rowNumber: 2, name: 'granja santa fe', phone: '5551234567'),
      ]);

      expect(report.updated, 1);
      expect(report.created, 0);
      expect(repo.customers.single.phone, '5551234567');
    });
  });
}
