import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';
import 'sale_service.dart';

/// One line in the POS cart.
@immutable
class CartLine {
  const CartLine({
    required this.key,
    required this.productId,
    this.variantId,
    this.imeiUnitId,
    this.imei,
    required this.name,
    required this.unitPrice,
    this.unitQty = 1,
    this.discount = Money.zero,
    this.unitId,
    this.unitSymbol,
    this.factor = 1,
    this.stock = 0,
  });

  final String key;
  final String productId;
  final String? variantId;
  final String? imeiUnitId;
  final String? imei;
  final String name;
  final Money unitPrice;
  final int unitQty;
  final Money discount;
  final String? unitId;
  final String? unitSymbol;
  final int factor;

  /// Base units in stock when added (for warnings only).
  final int stock;

  Money get total => unitPrice.times(unitQty) - discount;
  bool get isImei => imeiUnitId != null;

  CartLine copyWith({Money? unitPrice, int? unitQty, Money? discount, String? unitId, String? unitSymbol, int? factor}) =>
      CartLine(
        key: key,
        productId: productId,
        variantId: variantId,
        imeiUnitId: imeiUnitId,
        imei: imei,
        name: name,
        unitPrice: unitPrice ?? this.unitPrice,
        unitQty: unitQty ?? this.unitQty,
        discount: discount ?? this.discount,
        unitId: unitId ?? this.unitId,
        unitSymbol: unitSymbol ?? this.unitSymbol,
        factor: factor ?? this.factor,
        stock: stock,
      );

  SaleLineInput toInput() => SaleLineInput(
        productId: productId,
        variantId: variantId,
        imeiUnitId: imeiUnitId,
        unitId: unitId,
        unitQty: unitQty,
        unitPrice: unitPrice,
        discount: discount,
      );
}

@immutable
class CartState {
  const CartState({
    this.lines = const [],
    this.partyId,
    this.partyName,
    this.mode = SalePaymentMode.cash,
    this.method = PaymentMethod.cash,
    this.paidNow = Money.zero,
    this.discount = Money.zero,
    this.tax = Money.zero,
    this.delivery = Money.zero,
    this.note,
    this.qist,
  });

  final List<CartLine> lines;
  final String? partyId;
  final String? partyName;
  final SalePaymentMode mode;
  final PaymentMethod method;
  final Money paidNow;
  final Money discount;
  final Money tax;
  final Money delivery;
  final String? note;
  final QistInput? qist;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (a, l) => a + l.unitQty);

  ({Money gross, Money lineDiscount, Money subtotal, Money total}) get totals => SaleService.totals(
        [for (final l in lines) l.toInput()],
        discount: discount,
        tax: tax,
        delivery: delivery,
      );

  Money get grandTotal => totals.total + (qist?.markup ?? Money.zero);

  CartState copyWith({
    List<CartLine>? lines,
    String? partyId,
    String? partyName,
    bool clearParty = false,
    SalePaymentMode? mode,
    PaymentMethod? method,
    Money? paidNow,
    Money? discount,
    Money? tax,
    Money? delivery,
    String? note,
    QistInput? qist,
    bool clearQist = false,
  }) =>
      CartState(
        lines: lines ?? this.lines,
        partyId: clearParty ? null : (partyId ?? this.partyId),
        partyName: clearParty ? null : (partyName ?? this.partyName),
        mode: mode ?? this.mode,
        method: method ?? this.method,
        paidNow: paidNow ?? this.paidNow,
        discount: discount ?? this.discount,
        tax: tax ?? this.tax,
        delivery: delivery ?? this.delivery,
        note: note ?? this.note,
        qist: clearQist ? null : (qist ?? this.qist),
      );

  SaleInput toInput({bool priceOverrideApproved = false}) => SaleInput(
        partyId: partyId,
        lines: [for (final l in lines) l.toInput()],
        discount: discount,
        tax: tax,
        delivery: delivery,
        mode: mode,
        paidNow: paidNow,
        method: mode == SalePaymentMode.cash ? PaymentMethod.cash : method,
        note: note,
        qist: mode == SalePaymentMode.qist ? qist : null,
        priceOverrideApproved: priceOverrideApproved,
      );
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  /// Adds one of a product (or the given IMEI unit). Tapping the same
  /// non-IMEI product again increases its quantity.
  void add({
    required String productId,
    String? variantId,
    required String name,
    required Money price,
    String? imeiUnitId,
    String? imei,
    int stock = 0,
  }) {
    final lines = [...state.lines];
    if (imeiUnitId != null) {
      if (lines.any((l) => l.imeiUnitId == imeiUnitId)) return;
      lines.add(CartLine(
        key: newId(),
        productId: productId,
        variantId: variantId,
        imeiUnitId: imeiUnitId,
        imei: imei,
        name: name,
        unitPrice: price,
        stock: stock,
      ));
    } else {
      final i = lines.indexWhere((l) => l.productId == productId && l.variantId == variantId && l.unitId == null);
      if (i >= 0) {
        lines[i] = lines[i].copyWith(unitQty: lines[i].unitQty + 1);
      } else {
        lines.add(CartLine(
          key: newId(),
          productId: productId,
          variantId: variantId,
          name: name,
          unitPrice: price,
          stock: stock,
        ));
      }
    }
    state = state.copyWith(lines: lines);
  }

  void update(String key, CartLine Function(CartLine) change) {
    state = state.copyWith(lines: [for (final l in state.lines) l.key == key ? change(l) : l]);
  }

  void setQty(String key, int qty) {
    if (qty <= 0) return remove(key);
    update(key, (l) => l.isImei ? l : l.copyWith(unitQty: qty));
  }

  void remove(String key) => state = state.copyWith(lines: state.lines.where((l) => l.key != key).toList());

  void setParty(String? id, String? name) =>
      state = id == null ? state.copyWith(clearParty: true) : state.copyWith(partyId: id, partyName: name);

  void setMode(SalePaymentMode mode) => state = state.copyWith(mode: mode, clearQist: mode != SalePaymentMode.qist);
  void setMethod(PaymentMethod m) => state = state.copyWith(method: m);
  void setPaidNow(Money m) => state = state.copyWith(paidNow: m);
  void setDiscount(Money m) => state = state.copyWith(discount: m);
  void setTax(Money m) => state = state.copyWith(tax: m);
  void setDelivery(Money m) => state = state.copyWith(delivery: m);
  void setNote(String? n) => state = state.copyWith(note: n);
  void setQist(QistInput q) => state = state.copyWith(qist: q, mode: SalePaymentMode.qist);

  void clear() => state = const CartState();
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
