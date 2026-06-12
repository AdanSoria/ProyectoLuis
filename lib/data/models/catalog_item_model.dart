import 'dart:convert';

import '../../domain/entities/catalog_item.dart';
import '../../domain/entities/product_variant.dart';

/// Mapper entre la entidad de dominio y la fila SQLite / payload JSON.
/// Las llaves van en snake_case español: el mismo contrato sirve para la
/// base local y para el backend REST (Laravel/Node) sin traducción.
class CatalogItemModel {
  CatalogItemModel._();

  static Map<String, Object?> toRow(CatalogItem item) {
    // Para productos, las columnas de precio/stock del catálogo reflejan
    // a la variante default (solo como espejo de ordenamiento/lectura
    // rápida; la verdad del stock vive en la tabla `variantes`).
    final defaultVariant = item is Product ? item.defaultVariant : null;
    return {
      'id': item.id,
      'tipo': item.isService ? 'servicio' : 'producto',
      'nombre': item.name,
      'categoria': item.category,
      'unidad': defaultVariant?.unit ?? item.unit,
      'precio_costo': defaultVariant?.costPriceCents ?? item.costPriceCents,
      'precio_venta': defaultVariant?.salePriceCents ?? item.salePriceCents,
      'stock': defaultVariant?.stock,
      'activo': item.active ? 1 : 0,
      'creado_en': item.createdAt.toIso8601String(),
      'actualizado_en': item.updatedAt.toIso8601String(),
    };
  }

  /// Construye la entidad. Para productos, [variantRows] debe traer sus
  /// variantes (la default primero); si llega vacío se proyecta una
  /// default desde las columnas espejo del catálogo (datos legados).
  static CatalogItem fromRow(
    Map<String, Object?> row, {
    List<Map<String, Object?>> variantRows = const [],
  }) {
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

    var variants = [for (final v in variantRows) variantFromRow(v)];
    variants.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    if (variants.isEmpty) {
      variants = [
        ProductVariant(
          id: id,
          productId: id,
          name: 'Estándar',
          costPriceCents: cost,
          salePriceCents: sale,
          stock: (row['stock'] as num?)?.toDouble() ?? 0,
          unit: unit,
          contentUnits: 1,
          isDefault: true,
        ),
      ];
    }

    final defaultVariant = variants.first;
    return Product(
      id: id,
      name: name,
      category: category,
      costPriceCents: defaultVariant.costPriceCents,
      salePriceCents: defaultVariant.salePriceCents,
      unit: defaultVariant.unit,
      active: active,
      createdAt: createdAt,
      updatedAt: updatedAt,
      stock: defaultVariant.stock,
      variants: variants,
    );
  }

  // ------------------------------------------------------------ variantes

  static Map<String, Object?> variantToRow(
    ProductVariant v,
    DateTime createdAt,
    DateTime updatedAt,
  ) =>
      {
        'id': v.id,
        'producto_id': v.productId,
        'nombre': v.name,
        'sku': v.sku,
        'precio_costo': v.costPriceCents,
        'precio_venta': v.salePriceCents,
        'stock': v.stock,
        'unidad': v.unit,
        'contenido': v.contentUnits,
        'es_default': v.isDefault ? 1 : 0,
        'activo': v.active ? 1 : 0,
        'precios_volumen': v.priceTiers.isEmpty
            ? null
            : jsonEncode([
                for (final t in v.priceTiers)
                  {'min': t.minQuantity, 'precio': t.unitPriceCents},
              ]),
        'creado_en': createdAt.toIso8601String(),
        'actualizado_en': updatedAt.toIso8601String(),
      };

  static ProductVariant variantFromRow(Map<String, Object?> row) {
    final tiersJson = row['precios_volumen'] as String?;
    var tiers = const <PriceTier>[];
    if (tiersJson != null && tiersJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(tiersJson) as List;
        tiers = [
          for (final t in decoded.whereType<Map>())
            PriceTier(
              minQuantity: (t['min'] as num).toDouble(),
              unitPriceCents: (t['precio'] as num).toInt(),
            ),
        ];
      } on Exception {
        tiers = const []; // JSON corrupto: variante sin escalones
      }
    }

    return ProductVariant(
      id: row['id'] as String,
      productId: row['producto_id'] as String,
      name: row['nombre'] as String,
      sku: row['sku'] as String?,
      costPriceCents: (row['precio_costo'] as num).toInt(),
      salePriceCents: (row['precio_venta'] as num).toInt(),
      stock: (row['stock'] as num?)?.toDouble() ?? 0,
      unit: (row['unidad'] as String?) ?? 'pieza',
      contentUnits: (row['contenido'] as num?)?.toDouble() ?? 1,
      isDefault: (row['es_default'] as num? ?? 0) == 1,
      active: (row['activo'] as num? ?? 1) == 1,
      priceTiers: tiers,
    );
  }

  /// Payload para la cola de sincronización: fila del catálogo + variantes.
  static Map<String, dynamic> toSyncJson(CatalogItem item) => {
        ...toRow(item),
        if (item is Product)
          'variantes': [
            for (final v in item.variants.isEmpty
                ? [item.defaultVariant]
                : item.variants)
              variantToRow(v, item.createdAt, item.updatedAt),
          ],
      };
}
