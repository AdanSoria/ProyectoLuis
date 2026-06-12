import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../entities/catalog_item.dart';
import '../entities/product_variant.dart';
import '../repositories/catalog_repository.dart';

/// **Desensamble dinámico (bulk breaking)**: convierte presentaciones
/// mayores en menores para vender fraccionado.
///
/// Ej.: romper 1 "Costal 40 kg" (contenido 40) hacia "Granel kg"
/// (contenido 1) descuenta 1 del costal y suma 40 al granel.
class BreakVariantUseCase {
  BreakVariantUseCase({required CatalogRepository catalog})
      : _catalog = catalog;

  final CatalogRepository _catalog;

  /// Devuelve las unidades acreditadas a la variante destino.
  Future<Result<double>> call({
    required String productId,
    required String sourceVariantId,
    required String targetVariantId,
    required double quantity,
  }) async {
    if (quantity <= 0) {
      return const Err(ValidationFailure('La cantidad debe ser mayor a 0.'));
    }
    if (sourceVariantId == targetVariantId) {
      return const Err(
          ValidationFailure('Elige dos presentaciones distintas.'));
    }

    final item = await _catalog.getById(productId);
    if (item is! Product) {
      return const Err(NotFoundFailure('El producto ya no existe.'));
    }

    ProductVariant? find(String id) =>
        item.variants.where((v) => v.id == id).firstOrNull;
    final source = find(sourceVariantId);
    final target = find(targetVariantId);
    if (source == null || target == null) {
      return const Err(
          NotFoundFailure('Alguna de las presentaciones ya no existe.'));
    }
    if (source.contentUnits <= 0 || target.contentUnits <= 0) {
      return const Err(ValidationFailure(
          'Define el contenido de ambas presentaciones para pasar a granel.'));
    }
    if (source.contentUnits <= target.contentUnits) {
      return Err(ValidationFailure(
          'Solo se fracciona de mayor a menor: "${source.name}" no contiene '
          'a "${target.name}".'));
    }
    if (!source.hasStockFor(quantity)) {
      return Err(InsufficientStockFailure(
          '${item.name} · ${source.name}', source.stock));
    }

    // La conversión y la atomicidad las garantiza el repositorio.
    return _catalog.breakVariant(
      sourceVariantId: sourceVariantId,
      targetVariantId: targetVariantId,
      quantity: quantity,
    );
  }
}
