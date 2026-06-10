import '../../core/utils/result.dart';
import '../entities/catalog_item.dart';

abstract class CatalogRepository {
  Future<List<CatalogItem>> getAll({bool includeInactive = false});

  Future<CatalogItem?> getById(String id);

  /// Inserta o actualiza el artículo y encola la operación en el Outbox
  /// dentro de la misma transacción local.
  Future<Result<CatalogItem>> save(CatalogItem item, {required bool isNew});

  /// Ajuste manual de existencias (+/-). Registra el movimiento de
  /// inventario y encola la sincronización de forma atómica.
  Future<Result<void>> adjustStock({
    required String productId,
    required double delta,
    required String reason,
  });
}
