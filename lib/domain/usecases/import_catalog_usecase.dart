import '../../core/utils/id_generator.dart';
import '../entities/catalog_item.dart';
import '../entities/product_variant.dart';
import '../repositories/catalog_repository.dart';

/// Fila descartada durante una importación, con su motivo legible.
class SkippedRow {
  const SkippedRow({required this.rowNumber, required this.reason});

  /// Número de fila en el archivo original (contando el encabezado).
  final int rowNumber;
  final String reason;
}

/// Resultado de una importación masiva.
class ImportReport {
  const ImportReport({
    required this.created,
    required this.updated,
    required this.skipped,
  });

  final int created;
  final int updated;
  final List<SkippedRow> skipped;

  int get total => created + updated + skipped.length;
  bool get hasErrors => skipped.isNotEmpty;
}

/// Fila del archivo ya mapeada a campos de catálogo por el asistente.
/// Los campos opcionales en `null` significan "la columna no se mapeó":
/// al actualizar un artículo existente se conserva su valor actual.
class CatalogRowInput {
  const CatalogRowInput({
    required this.rowNumber,
    required this.name,
    required this.salePriceCents,
    this.costPriceCents,
    this.stock,
    this.category = '',
    this.unit = '',
    this.isService = false,
  });

  final int rowNumber;
  final String name;
  final int salePriceCents;
  final int? costPriceCents;
  final double? stock;
  final String category;
  final String unit;
  final bool isService;
}

/// Importa (o actualiza) el catálogo desde una tabla externa (Excel/CSV).
///
/// Reglas:
/// - El nombre identifica al artículo (sin distinguir mayúsculas/acentos
///   exactos): si ya existe se ACTUALIZAN precios/stock/categoría; si no,
///   se crea con UUID v4 nuevo.
/// - Cada alta/actualización pasa por el repositorio normal, así que
///   también queda encolada en el Outbox para sincronizar.
/// - Nunca lanza por una fila mala: la reporta en [ImportReport.skipped].
class ImportCatalogUseCase {
  ImportCatalogUseCase({
    required CatalogRepository catalog,
    required IdGenerator idGenerator,
    DateTime Function()? now,
  })  : _catalog = catalog,
        _ids = idGenerator,
        _now = now ?? DateTime.now;

  final CatalogRepository _catalog;
  final IdGenerator _ids;
  final DateTime Function() _now;

  Future<ImportReport> call(List<CatalogRowInput> rows) async {
    final existing = await _catalog.getAll(includeInactive: true);
    final byName = <String, CatalogItem>{
      for (final item in existing) _normalize(item.name): item,
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
      if (row.salePriceCents <= 0) {
        skipped.add(SkippedRow(
            rowNumber: row.rowNumber, reason: 'Precio de venta inválido'));
        continue;
      }
      if ((row.costPriceCents ?? 0) < 0 || (row.stock ?? 0) < 0) {
        skipped.add(SkippedRow(
            rowNumber: row.rowNumber, reason: 'Valores negativos'));
        continue;
      }

      final now = _now();
      final category = row.category.trim();
      final unit = row.unit.trim();
      final found = byName[_normalize(name)];

      if (found == null) {
        final CatalogItem item;
        if (row.isService) {
          item = Service(
            id: _ids.newId(),
            name: name,
            category: category.isEmpty ? 'General' : category,
            costPriceCents: row.costPriceCents ?? 0,
            salePriceCents: row.salePriceCents,
            createdAt: now,
            updatedAt: now,
          );
        } else {
          // Producto simple: nace con su variante default (id compartido).
          item = Product.simple(
            id: _ids.newId(),
            name: name,
            category: category.isEmpty ? 'General' : category,
            costPriceCents: row.costPriceCents ?? 0,
            salePriceCents: row.salePriceCents,
            unit: unit.isEmpty ? 'pieza' : unit,
            stock: row.stock ?? 0,
            createdAt: now,
            updatedAt: now,
          );
        }

        final result = await _catalog.save(item, isNew: true);
        result.fold(
          ok: (saved) {
            created++;
            byName[_normalize(name)] = saved;
          },
          err: (failure) => skipped.add(
              SkippedRow(rowNumber: row.rowNumber, reason: failure.message)),
        );
        continue;
      }

      // Existente: el archivo manda en lo que sí trae mapeado; lo demás
      // se conserva. Si estaba oculto, la importación lo reactiva.
      // En productos solo se toca la variante DEFAULT; las demás
      // presentaciones quedan intactas.
      final CatalogItem merged;
      switch (found) {
        case final Product p:
          final defaultVariant = p.defaultVariant.copyWith(
            salePriceCents: row.salePriceCents,
            costPriceCents: row.costPriceCents,
            stock: row.stock,
            unit: unit.isEmpty ? null : unit,
          );
          final others = p.variants.length > 1
              ? p.variants.sublist(1)
              : const <ProductVariant>[];
          merged = p.copyWith(
            salePriceCents: defaultVariant.salePriceCents,
            costPriceCents: defaultVariant.costPriceCents,
            stock: defaultVariant.stock,
            category: category.isEmpty ? null : category,
            unit: unit.isEmpty ? null : unit,
            active: true,
            updatedAt: now,
            variants: [defaultVariant, ...others],
          );
        case final Service s:
          merged = s.copyWith(
            salePriceCents: row.salePriceCents,
            costPriceCents: row.costPriceCents,
            category: category.isEmpty ? null : category,
            active: true,
            updatedAt: now,
          );
      }

      final result = await _catalog.save(merged, isNew: false);
      result.fold(
        ok: (saved) {
          updated++;
          byName[_normalize(name)] = saved;
        },
        err: (failure) => skipped.add(
            SkippedRow(rowNumber: row.rowNumber, reason: failure.message)),
      );
    }

    return ImportReport(created: created, updated: updated, skipped: skipped);
  }

  String _normalize(String value) {
    var v = value.trim().toLowerCase();
    const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
    accents.forEach((from, to) => v = v.replaceAll(from, to));
    return v;
  }
}
