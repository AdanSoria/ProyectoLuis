import '../../domain/entities/catalog_item.dart';

/// Mapper entre la entidad de dominio y la fila SQLite / payload JSON.
/// Las llaves van en snake_case español: el mismo contrato sirve para la
/// base local y para el backend REST (Laravel/Node) sin traducción.
class CatalogItemModel {
  CatalogItemModel._();

  static Map<String, Object?> toRow(CatalogItem item) => {
        'id': item.id,
        'tipo': item.isService ? 'servicio' : 'producto',
        'nombre': item.name,
        'categoria': item.category,
        'unidad': item.unit,
        'precio_costo': item.costPriceCents,
        'precio_venta': item.salePriceCents,
        'stock': item is Product ? item.stock : null,
        'activo': item.active ? 1 : 0,
        'creado_en': item.createdAt.toIso8601String(),
        'actualizado_en': item.updatedAt.toIso8601String(),
      };

  static CatalogItem fromRow(Map<String, Object?> row) {
    final isService = row['tipo'] == 'servicio';
    final id = row['id'] as String;
    final name = row['nombre'] as String;
    final category = row['categoria'] as String;
    final unit = (row['unidad'] as String?) ?? 'pieza';
    final cost = (row['precio_costo'] as num).toInt();
    final sale = (row['precio_venta'] as num).toInt();
    final active = (row['activo'] as num? ?? 1) == 1;
    final createdAt = DateTime.parse(row['creado_en'] as String);
    final updatedAt = DateTime.parse(row['actualizado_en'] as String);

    if (isService) {
      return Service(
        id: id,
        name: name,
        category: category,
        costPriceCents: cost,
        salePriceCents: sale,
        unit: unit,
        active: active,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }
    return Product(
      id: id,
      name: name,
      category: category,
      costPriceCents: cost,
      salePriceCents: sale,
      unit: unit,
      active: active,
      createdAt: createdAt,
      updatedAt: updatedAt,
      stock: (row['stock'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Payload para la cola de sincronización (idéntico a la fila).
  static Map<String, dynamic> toSyncJson(CatalogItem item) => toRow(item);
}
