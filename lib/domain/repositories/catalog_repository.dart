import '../../core/utils/result.dart';
import '../entities/catalog_item.dart';

abstract class CatalogRepository {
  Future<List<CatalogItem>> getAll({bool includeInactive = false});

  Future<CatalogItem?> getById(String id);

  /// Inserta o actualiza el artículo (incluidas sus variantes) y encola
  /// la operación en el Outbox dentro de la misma transacción local.
  Future<Result<CatalogItem>> save(CatalogItem item, {required bool isNew});

  /// Ajuste manual de existencias (+/-) de UNA variante. Registra el
  /// movimiento de inventario y encola la sincronización atómicamente.
  /// Para productos simples, el id de la variante default es el mismo
  /// id del producto.
  Future<Result<void>> adjustStock({
    required String variantId,
    required double delta,
    required String reason,
  });

  /// **Desensamble (bulk breaking)**: convierte [quantity] unidades de la
  /// variante origen en su equivalente de la variante destino, usando la
  /// proporción de `contentUnits` (1 costal de 50 kg -> 50 de granel kg).
  /// Atómico: ambos stocks + movimientos + Outbox, todo o nada.
  Future<Result<double>> breakVariant({
    required String sourceVariantId,
    required String targetVariantId,
    required double quantity,
  });
}
