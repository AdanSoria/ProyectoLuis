import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../data/models/catalog_item_model.dart';
import '../../data/models/customer_model.dart';
import '../../domain/entities/cart_line.dart';
import '../../domain/entities/catalog_item.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/product_variant.dart';

/// Estado inmutable del carrito de compras.
///
/// Descuento del ticket:
/// - con cliente asignado, su `discount_percentage` se aplica solo
///   ([autoDiscountCents]);
/// - el cajero puede ANULARLO con un monto manual
///   ([manualDeductionsCents]); `null` = respetar el automático.
class CartState {
  const CartState({
    this.lines = const [],
    this.customer,
    this.manualDeductionsCents,
  });

  final List<CartLine> lines;

  /// Cliente asignado a la venta (fidelización).
  final Customer? customer;

  /// Descuento manual del cajero; `null` = usar el del perfil del cliente.
  final int? manualDeductionsCents;

  int get subtotalCents => lines.fold(0, (sum, l) => sum + l.totalCents);

  /// Descuento sugerido por el perfil del cliente.
  int get autoDiscountCents => customer?.discountFor(subtotalCents) ?? 0;

  bool get isManualDiscount => manualDeductionsCents != null;

  int get deductionsCents => manualDeductionsCents ?? autoDiscountCents;

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

  bool _sameSlot(CartLine a, CartLine b) =>
      a.item.id == b.item.id &&
      (a.effectiveVariant?.id) == (b.effectiveVariant?.id);

  /// Un tap = un artículo más (de la variante indicada). Fricción cero.
  void add(CatalogItem item, {ProductVariant? variant, double quantity = 1}) {
    final incoming =
        CartLine(item: item, quantity: quantity, variant: variant);
    final index = state.lines.indexWhere((l) => _sameSlot(l, incoming));
    final lines = [...state.lines];
    if (index >= 0) {
      lines[index] =
          lines[index].copyWith(quantity: lines[index].quantity + quantity);
    } else {
      lines.add(incoming);
    }
    _update(lines: lines);
  }

  void setQuantity(CartLine target, double quantity) {
    if (quantity <= 0) {
      remove(target);
      return;
    }
    _update(lines: [
      for (final l in state.lines)
        if (_sameSlot(l, target)) l.copyWith(quantity: quantity) else l,
    ]);
  }

  void increment(CartLine line) => setQuantity(line, line.quantity + 1);

  void decrement(CartLine line) => setQuantity(line, line.quantity - 1);

  void remove(CartLine target) {
    _update(lines: state.lines.where((l) => !_sameSlot(l, target)).toList());
  }

  /// Regateo: fija (o quita con `null`) el precio unitario negociado.
  void setPriceOverride(CartLine target, int? unitPriceCents) {
    _update(lines: [
      for (final l in state.lines)
        if (_sameSlot(l, target))
          l.copyWith(priceOverride: () => unitPriceCents)
        else
          l,
    ]);
  }

  /// Asigna el cliente: su descuento de perfil aplica automáticamente
  /// (mientras no haya un descuento manual).
  void setCustomer(Customer? customer) {
    state = CartState(
      lines: state.lines,
      customer: customer,
      manualDeductionsCents: state.manualDeductionsCents,
    );
    unawaited(_persistDraft());
  }

  /// Anula el descuento automático con un monto manual; `null` regresa
  /// al descuento del perfil.
  void setManualDeductions(int? cents) {
    state = CartState(
      lines: state.lines,
      customer: state.customer,
      manualDeductionsCents: cents == null ? null : math.max(0, cents),
    );
    unawaited(_persistDraft());
  }

  void clear() {
    state = const CartState();
    unawaited(_persistDraft());
  }

  void _update({List<CartLine>? lines}) {
    state = CartState(
      lines: lines ?? state.lines,
      customer: state.customer,
      manualDeductionsCents: state.manualDeductionsCents,
    );
    unawaited(_persistDraft());
  }

  // ------------------------------------------------- borrador persistente

  Future<void> _persistDraft() async {
    final draft = jsonEncode({
      'manual_deducciones': state.manualDeductionsCents,
      'cliente':
          state.customer == null ? null : CustomerModel.toRow(state.customer!),
      'lineas': [
        for (final l in state.lines)
          {
            'cantidad': l.quantity,
            'precio_manual': l.priceOverrideCents,
            'item': CatalogItemModel.toRow(l.item),
            'variante': l.effectiveVariant == null
                ? null
                : CatalogItemModel.variantToRow(
                    l.effectiveVariant!, l.item.createdAt, l.item.updatedAt),
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
        final variantMap = map['variante'];
        lines.add(CartLine(
          item: item,
          quantity: (map['cantidad'] as num).toDouble(),
          variant: variantMap == null
              ? null
              : CatalogItemModel.variantFromRow(
                  Map<String, Object?>.from(variantMap as Map)),
          priceOverrideCents: (map['precio_manual'] as num?)?.toInt(),
        ));
      }

      final customerMap = decoded['cliente'];

      if (!mounted) return;
      state = CartState(
        lines: lines,
        customer: customerMap == null
            ? null
            : CustomerModel.fromRow(
                Map<String, Object?>.from(customerMap as Map)),
        manualDeductionsCents:
            (decoded['manual_deducciones'] as num?)?.toInt(),
      );
    } on Exception {
      // Borrador corrupto: se descarta en silencio, nunca debe tirar la app.
      await _db.setKv(_draftKey, '');
    }
  }
}
