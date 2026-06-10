import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../data/models/catalog_item_model.dart';
import '../../domain/entities/cart_line.dart';
import '../../domain/entities/catalog_item.dart';

/// Estado inmutable del carrito de compras.
class CartState {
  const CartState({this.lines = const [], this.deductionsCents = 0});

  final List<CartLine> lines;

  /// Descuento del ticket en centavos.
  final int deductionsCents;

  int get subtotalCents => lines.fold(0, (sum, l) => sum + l.totalCents);
  int get totalCents => math.max(0, subtotalCents - deductionsCents);
  double get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);
  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;
}

/// Carrito interactivo y **persistente**: cada mutación se respalda como
/// borrador en SQLite (kv_store), de modo que un cierre accidental de la
/// app no pierde la venta a medio capturar.
class CartController extends StateNotifier<CartState> {
  CartController(this._db) : super(const CartState()) {
    unawaited(_restoreDraft());
  }

  static const _draftKey = 'cart_draft';

  final AppDatabase _db;

  /// Un tap = un artículo más. Fricción cero.
  void add(CatalogItem item, [double quantity = 1]) {
    final index = state.lines.indexWhere((l) => l.item.id == item.id);
    final lines = [...state.lines];
    if (index >= 0) {
      lines[index] =
          lines[index].copyWith(quantity: lines[index].quantity + quantity);
    } else {
      lines.add(CartLine(item: item, quantity: quantity));
    }
    _update(lines: lines);
  }

  void setQuantity(String itemId, double quantity) {
    if (quantity <= 0) {
      remove(itemId);
      return;
    }
    final lines = [
      for (final l in state.lines)
        if (l.item.id == itemId) l.copyWith(quantity: quantity) else l,
    ];
    _update(lines: lines);
  }

  void increment(String itemId) {
    final line = state.lines.where((l) => l.item.id == itemId).firstOrNull;
    if (line != null) setQuantity(itemId, line.quantity + 1);
  }

  void decrement(String itemId) {
    final line = state.lines.where((l) => l.item.id == itemId).firstOrNull;
    if (line != null) setQuantity(itemId, line.quantity - 1);
  }

  void remove(String itemId) {
    _update(lines: state.lines.where((l) => l.item.id != itemId).toList());
  }

  void setDeductions(int cents) {
    _update(deductionsCents: math.max(0, cents));
  }

  void clear() => _update(lines: const [], deductionsCents: 0);

  void _update({List<CartLine>? lines, int? deductionsCents}) {
    state = CartState(
      lines: lines ?? state.lines,
      deductionsCents: deductionsCents ?? state.deductionsCents,
    );
    unawaited(_persistDraft());
  }

  // ------------------------------------------------- borrador persistente

  Future<void> _persistDraft() async {
    final draft = jsonEncode({
      'deducciones': state.deductionsCents,
      'lineas': [
        for (final l in state.lines)
          {
            'cantidad': l.quantity,
            'item': CatalogItemModel.toRow(l.item),
          },
      ],
    });
    await _db.setKv(_draftKey, draft);
  }

  Future<void> _restoreDraft() async {
    try {
      final raw = await _db.getKv(_draftKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final lines = <CartLine>[];
      for (final entry in (decoded['lineas'] as List? ?? const [])) {
        final map = entry as Map<String, dynamic>;
        final item = CatalogItemModel.fromRow(
            Map<String, Object?>.from(map['item'] as Map));
        lines.add(CartLine(
          item: item,
          quantity: (map['cantidad'] as num).toDouble(),
        ));
      }

      if (!mounted) return;
      state = CartState(
        lines: lines,
        deductionsCents: (decoded['deducciones'] as num? ?? 0).toInt(),
      );
    } on Exception {
      // Borrador corrupto: se descarta en silencio, nunca debe tirar la app.
      await _db.setKv(_draftKey, '');
    }
  }
}
