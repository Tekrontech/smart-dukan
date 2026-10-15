import 'package:drift/drift.dart';

import '../../../core/accounting/allocation.dart';
import '../../../core/accounting/ledger_queries.dart';
import '../../../core/accounting/posting.dart';
import '../../../core/accounting/system_accounts.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';
import '../../pro_mobile/qist/application/qist_schedule_sync.dart';

class SaleLineInput {
  const SaleLineInput({
    required this.productId,
    this.variantId,
    this.imeiUnitId,
    this.unitId,
    this.unitQty = 1,
    required this.unitPrice,
    this.discount = Money.zero,
  });

  final String productId;
  final String? variantId;
  final String? imeiUnitId;

  /// Unit sold in; null = the product's base unit.
  final String? unitId;
  final int unitQty;

  /// Price per [unitId].
  final Money unitPrice;
  final Money discount;

  Money get lineTotal => unitPrice.times(unitQty) - discount;
}

/// Instalment plan terms for a qist sale (Mobile Shop Pro, spec 5.9).
class QistInput {
  const QistInput({
    required this.markup,
    required this.downPayment,
    required this.installments,
    this.frequency = QistFrequency.monthly,
    this.startDate,
    this.guarantorName,
    this.guarantorPhone,
  });

  final Money markup;
  final Money downPayment;
  final int installments;
  final QistFrequency frequency;

  /// First instalment due date; defaults to one period after the sale.
  final DateTime? startDate;
  final String? guarantorName;
  final String? guarantorPhone;
}

class SaleInput {
  const SaleInput({
    this.partyId,
    required this.lines,
    this.discount = Money.zero,
    this.tax = Money.zero,
    this.delivery = Money.zero,
    this.mode = SalePaymentMode.cash,
    this.paidNow,
    this.method = PaymentMethod.cash,
    this.note,
    this.qist,
    this.priceOverrideApproved = false,
  });

  final String? partyId;
  final List<SaleLineInput> lines;
  final Money discount;
  final Money tax;
  final Money delivery;
  final SalePaymentMode mode;

  /// Amount paid at the counter for [SalePaymentMode.mixed].
  final Money? paidNow;

  /// Method for the paid part (cash, bank, JazzCash, Easypaisa).
  final PaymentMethod method;
  final String? note;
  final QistInput? qist;

  /// Owner PIN was entered to allow a price below `min_sale_price`.
  final bool priceOverrideApproved;
}

class SaleResult {
  const SaleResult({required this.saleId, required this.invoiceNo, required this.total, this.planId});

  final String saleId;
  final String invoiceNo;
  final Money total;
  final String? planId;
}

class SaleReturnLine {
  const SaleReturnLine({required this.saleItemId, required this.qty});

  final String saleItemId;

  /// Base units returned.
  final int qty;
}

/// Sales, sale returns and sale reversal (spec 5.3, 8, 8.1).
class SaleService {
  SaleService(this.db, this.ctx) : posting = PostingService(db, ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  final PostingService posting;

  /// Totals for a cart, without saving. Used by the POS screen.
  static ({Money gross, Money lineDiscount, Money subtotal, Money total}) totals(
    List<SaleLineInput> lines, {
    Money discount = Money.zero,
    Money tax = Money.zero,
    Money delivery = Money.zero,
  }) {
    final gross = Money.sum(lines.map((l) => l.unitPrice.times(l.unitQty)));
    final lineDisc = Money.sum(lines.map((l) => l.discount));
    final subtotal = gross - lineDisc;
    return (gross: gross, lineDiscount: lineDisc, subtotal: subtotal, total: subtotal - discount + tax + delivery);
  }

  /// Saves a sale: document, stock, COGS and a balanced journal entry in
  /// ONE transaction (spec 5.3 step 7).
  Future<SaleResult> createSale(SaleInput input) => posting.run((p) => _create(p, input));

  Future<SaleResult> _create(Posting p, SaleInput input) async {
    if (input.lines.isEmpty) throw const PostingException(PostingError.emptyDocument);
    if (input.discount.isNegative || input.tax.isNegative || input.delivery.isNegative) {
      throw const PostingException(PostingError.invalidAmount);
    }
    final qist = input.qist;
    if ((input.mode == SalePaymentMode.qist) != (qist != null)) {
      throw const PostingException(PostingError.invalidInput, 'qist terms');
    }

    // Resolve lines: products, unit factors, IMEI units.
    final resolved = <_Line>[];
    final seenImei = <String>{};
    for (final l in input.lines) {
      if (l.unitQty <= 0 || l.unitPrice.isNegative || l.discount.isNegative) {
        throw const PostingException(PostingError.invalidInput, 'line qty/price');
      }
      if (l.discount > l.unitPrice.times(l.unitQty)) throw const PostingException(PostingError.invalidAmount);
      final product = await (db.select(db.products)..where((x) => x.id.equals(l.productId))).getSingleOrNull();
      if (product == null) throw const PostingException(PostingError.notFound, 'product');
      final factor = await unitFactor(db, product, l.unitId);
      final qty = l.unitQty * factor;

      ImeiUnit? unit;
      if (product.tracksImei) {
        if (l.imeiUnitId == null) throw const PostingException(PostingError.imeiRequired);
        if (qty != 1) throw const PostingException(PostingError.invalidInput, 'one IMEI per line');
        if (!seenImei.add(l.imeiUnitId!)) throw const PostingException(PostingError.imeiDuplicate);
        unit = await (db.select(db.imeiUnits)..where((u) => u.id.equals(l.imeiUnitId!))).getSingleOrNull();
        if (unit == null || unit.status != ImeiStatus.inStock || unit.productId != product.id) {
          throw const PostingException(PostingError.imeiNotAvailable);
        }
      }
      if (product.minSalePrice.isPositive &&
          l.lineTotal < product.minSalePrice.times(qty) &&
          !input.priceOverrideApproved) {
        throw PostingException(PostingError.belowMinPrice, product.name);
      }
      resolved.add(_Line(l, product, qty, unit));
    }

    final t = totals(input.lines, discount: input.discount, tax: input.tax, delivery: input.delivery);
    if (input.discount > t.subtotal) throw const PostingException(PostingError.invalidAmount, 'discount');

    final markup = qist?.markup ?? Money.zero;
    final total = t.total + markup;
    Money paid;
    switch (input.mode) {
      case SalePaymentMode.cash:
      case SalePaymentMode.wallet:
        paid = total;
      case SalePaymentMode.udhaar:
        paid = Money.zero;
      case SalePaymentMode.mixed:
        paid = input.paidNow ?? Money.zero;
        if (paid.isNegative || paid > total) throw const PostingException(PostingError.overpayment);
      case SalePaymentMode.qist:
        if (!input.tax.isZero || !input.delivery.isZero) {
          throw const PostingException(PostingError.invalidInput, 'no tax/delivery on qist');
        }
        if (markup.isNegative || qist!.installments <= 0) throw const PostingException(PostingError.invalidInput);
        paid = qist.downPayment;
        if (paid.isNegative || paid > total) throw const PostingException(PostingError.overpayment);
    }
    final due = total - paid;
    if ((due.isPositive || input.mode == SalePaymentMode.qist) && input.partyId == null) {
      throw const PostingException(PostingError.partyRequired);
    }

    final business = await (db.select(db.businesses)..limit(1)).getSingle();
    final seq = await p.nextSeq('sale');
    final invoiceNo = docNumber(business.invoicePrefix, seq);
    final saleId = newId();
    final planId = qist != null ? newId() : null;

    await db.into(db.sales).insert(SalesCompanion.insert(
          id: saleId,
          businessId: p.businessId,
          createdAt: p.now,
          updatedAt: p.now,
          createdBy: Value(p.userId),
          invoiceSeq: seq,
          invoiceNo: invoiceNo,
          partyId: Value(input.partyId),
          date: p.now,
          gross: t.gross,
          subtotal: t.subtotal,
          discount: Value(input.discount),
          tax: Value(input.tax),
          delivery: Value(input.delivery),
          markup: Value(markup),
          total: total,
          paid: paid,
          paidMethod: input.method,
          due: due,
          paymentMode: input.mode,
          status: DocStatus.posted,
          note: Value(input.note),
        ));

    // Prorate the invoice discount by line total, then tax by net amount.
    final discShares = input.discount.allocate([for (final r in resolved) r.input.lineTotal.paisa]);
    final nets = [for (var i = 0; i < resolved.length; i++) resolved[i].input.lineTotal - discShares[i]];
    final taxShares = input.tax.allocate([for (final n in nets) n.paisa]);

    var cogs = Money.zero;
    for (var i = 0; i < resolved.length; i++) {
      final r = resolved[i];
      final out = await p.stockOut(
        productId: r.product.id,
        variantId: r.input.variantId,
        qty: r.qty,
        value: r.unit?.cost,
        type: StockMoveType.sale,
        refType: 'sale',
        refId: saleId,
        imeiUnitId: r.unit?.id,
        allowNegative: r.unit != null ? false : null,
      );
      cogs += out.value;
      final variant = r.input.variantId == null
          ? null
          : await (db.select(db.productVariants)..where((v) => v.id.equals(r.input.variantId!))).getSingleOrNull();
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
            id: newId(),
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            saleId: saleId,
            productId: r.product.id,
            variantId: Value(r.input.variantId),
            imeiUnitId: Value(r.unit?.id),
            description: variant == null ? r.product.name : '${r.product.name} ${variant.label}',
            unitId: Value(r.input.unitId),
            unitQty: r.input.unitQty,
            qty: r.qty,
            unitPrice: r.input.unitPrice,
            discount: Value(r.input.discount),
            lineTotal: r.input.lineTotal,
            netAmount: nets[i],
            taxAmount: Value(taxShares[i]),
            unitCostSnapshot: out.value.ratio(1, r.qty),
            costTotal: out.value,
          ));
      if (r.unit != null) {
        await (db.update(db.imeiUnits)..where((u) => u.id.equals(r.unit!.id))).write(ImeiUnitsCompanion(
          status: const Value(ImeiStatus.sold),
          saleRefId: Value(saleId),
          warrantyUntil: Value(r.product.warrantyDays > 0 ? p.now.add(Duration(days: r.product.warrantyDays)) : null),
          updatedAt: Value(p.now),
        ));
      }
    }

    // Journal (spec 8 + 8.1 invoice extras).
    final cashAcc = SysAccount.forMethod(input.method);
    final refType = planId != null ? 'qist' : null;
    if (qist != null) {
      // Qist: Dr AR T; Cr Sales P (gross, discount separately); Cr
      // DEFERRED_MARKUP M. Then the down payment and its markup share.
      p.dr(SysAccount.ar, total, partyId: input.partyId, refType: refType, refId: planId);
      p.dr(cashAcc, paid);
      p.cr(SysAccount.ar, paid, partyId: input.partyId, refType: refType, refId: planId);
      final earned = markupEarned(markup: markup, total: total, paidBefore: Money.zero, paidNow: paid);
      p.dr(SysAccount.deferredMarkup, earned);
      p.cr(SysAccount.markupIncome, earned);
      p.cr(SysAccount.deferredMarkup, markup);
    } else {
      p.dr(cashAcc, paid);
      p.dr(SysAccount.ar, due, partyId: input.partyId);
    }
    p.dr(SysAccount.discount, t.lineDiscount + input.discount);
    p.cr(SysAccount.sales, t.gross);
    p.cr(SysAccount.salesTaxPayable, input.tax);
    p.cr(SysAccount.deliveryIncome, input.delivery);
    p.dr(SysAccount.cogs, cogs);
    await p.commit(date: p.now, sourceType: 'sale', sourceId: saleId, memo: 'Sale $invoiceNo');

    if (qist != null) {
      await db.into(db.qistPlans).insert(QistPlansCompanion.insert(
            id: planId!,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            saleId: saleId,
            partyId: input.partyId!,
            guarantorName: Value(qist.guarantorName),
            guarantorPhone: Value(qist.guarantorPhone),
            cashPrice: total - markup,
            markup: markup,
            total: total,
            downPayment: paid,
            installments: qist.installments,
            frequency: qist.frequency,
            startDate: qist.startDate ?? _nextPeriod(p.now, qist.frequency),
            status: due.isPositive ? QistPlanStatus.active : QistPlanStatus.completed,
          ));
      final schedule = buildQistSchedule(
        financed: due,
        count: qist.installments,
        frequency: qist.frequency,
        start: qist.startDate ?? _nextPeriod(p.now, qist.frequency),
      );
      for (final row in schedule) {
        await db.into(db.qistSchedule).insert(QistScheduleCompanion.insert(
              id: newId(),
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              planId: planId,
              seq: row.seq,
              dueDate: row.due,
              amountDue: row.amount,
              status: row.amount.isZero ? QistRowStatus.paid : QistRowStatus.due,
            ));
      }
    } else if (input.partyId != null && due.isPositive) {
      // A customer advance pays this invoice automatically (spec 8.1).
      await Allocator(p).settleParty(input.partyId!);
    }

    await p.audit('sale', saleId, 'create', after: {'invoice': invoiceNo, 'total': total.paisa});
    return SaleResult(saleId: saleId, invoiceNo: invoiceNo, total: total, planId: planId);
  }

  static DateTime _nextPeriod(DateTime d, QistFrequency f) =>
      f == QistFrequency.weekly ? DateTime(d.year, d.month, d.day + 7) : DateTime(d.year, d.month + 1, d.day);

  /// Quantity already returned per sale item.
  Future<Map<String, ({int qty, Money amount, Money tax, Money cost})>> returnedSoFar(String saleId) async {
    final rows = await db.customSelect(
      'SELECT ri.sale_item_id AS id, SUM(ri.qty) AS q, SUM(ri.amount) AS a, SUM(ri.tax_amount) AS t, '
      'SUM(ri.cost_amount) AS c FROM sale_return_items ri JOIN sale_returns r ON r.id = ri.return_id '
      "WHERE r.sale_id = ? AND r.status = 'posted' GROUP BY ri.sale_item_id",
      variables: [Variable.withString(saleId)],
      readsFrom: {db.saleReturnItems, db.saleReturns},
    ).get();
    return {
      for (final r in rows)
        r.read<String>('id'): (
          qty: r.read<int>('q'),
          amount: Money(r.read<int>('a')),
          tax: Money(r.read<int>('t')),
          cost: Money(r.read<int>('c')),
        ),
    };
  }

  /// Sale return (spec 8.1). R first reduces what the customer still owes
  /// on the invoice; the rest is refunded now or kept as credit.
  Future<String> returnSale({
    required String saleId,
    required List<SaleReturnLine> lines,
    bool refundRemainder = true,
    PaymentMethod refundMethod = PaymentMethod.cash,
    String? note,
  }) {
    return posting.run((p) async {
      final sale = await (db.select(db.sales)..where((s) => s.id.equals(saleId))).getSingleOrNull();
      if (sale == null) throw const PostingException(PostingError.notFound);
      if (sale.status != DocStatus.posted) throw const PostingException(PostingError.alreadyReversed);
      if (sale.paymentMode == SalePaymentMode.qist) {
        throw const PostingException(PostingError.invalidInput, 'cancel the qist plan instead');
      }
      final wanted = lines.where((l) => l.qty > 0).toList();
      if (wanted.isEmpty) throw const PostingException(PostingError.emptyDocument);

      final items = {
        for (final i in await (db.select(db.saleItems)..where((x) => x.saleId.equals(saleId))).get()) i.id: i
      };
      final before = await returnedSoFar(saleId);
      final returnId = newId();
      final seq = await p.nextSeq('sale_return');

      var amount = Money.zero, tax = Money.zero, cost = Money.zero;
      final rows = <SaleReturnItemsCompanion>[];
      for (final l in wanted) {
        final item = items[l.saleItemId];
        if (item == null) throw const PostingException(PostingError.notFound, 'sale item');
        final done = before[item.id];
        final doneQty = done?.qty ?? 0;
        if (l.qty > item.qty - doneQty) throw const PostingException(PostingError.overReturn);
        final last = doneQty + l.qty == item.qty;
        final a = last ? item.netAmount - (done?.amount ?? Money.zero) : item.netAmount.ratio(l.qty, item.qty);
        final tx = last ? item.taxAmount - (done?.tax ?? Money.zero) : item.taxAmount.ratio(l.qty, item.qty);
        final c = last ? item.costTotal - (done?.cost ?? Money.zero) : item.costTotal.ratio(l.qty, item.qty);
        amount += a;
        tax += tx;
        cost += c;

        await p.stockIn(
          productId: item.productId,
          variantId: item.variantId,
          qty: l.qty,
          value: c,
          type: StockMoveType.saleReturn,
          refType: 'sale_return',
          refId: returnId,
          imeiUnitId: item.imeiUnitId,
        );
        if (item.imeiUnitId != null) {
          await (db.update(db.imeiUnits)..where((u) => u.id.equals(item.imeiUnitId!))).write(ImeiUnitsCompanion(
            status: const Value(ImeiStatus.inStock),
            saleRefId: const Value(null),
            warrantyUntil: const Value(null),
            updatedAt: Value(p.now),
          ));
        }
        rows.add(SaleReturnItemsCompanion.insert(
          id: newId(),
          businessId: p.businessId,
          createdAt: p.now,
          updatedAt: p.now,
          createdBy: Value(p.userId),
          returnId: returnId,
          saleItemId: item.id,
          productId: item.productId,
          variantId: Value(item.variantId),
          imeiUnitId: Value(item.imeiUnitId),
          qty: l.qty,
          amount: a,
          taxAmount: tx,
          costAmount: c,
        ));
      }

      final r = amount + tax;
      final openDue = await LedgerQueries(db).saleOpenDue(sale);
      final applied = Money.min(r, Money.max(openDue, Money.zero));
      final remainder = r - applied;
      final refund = sale.partyId == null || refundRemainder;

      p.dr(SysAccount.salesReturns, amount);
      p.dr(SysAccount.salesTaxPayable, tax);
      p.cr(SysAccount.ar, applied, partyId: sale.partyId);
      if (refund) {
        p.cr(SysAccount.forMethod(refundMethod), remainder);
      } else {
        p.cr(SysAccount.ar, remainder, partyId: sale.partyId);
      }
      p.cr(SysAccount.cogs, cost);

      await db.into(db.saleReturns).insert(SaleReturnsCompanion.insert(
            id: returnId,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            returnSeq: seq,
            returnNo: docNumber('SR-', seq),
            saleId: saleId,
            partyId: Value(sale.partyId),
            date: p.now,
            amount: r,
            appliedToDue: applied,
            refunded: refund ? remainder : Money.zero,
            refundMethod: Value(refund && remainder.isPositive ? refundMethod : null),
            keptAsCredit: refund ? Money.zero : remainder,
            status: DocStatus.posted,
            note: Value(note),
          ));
      for (final row in rows) {
        await db.into(db.saleReturnItems).insert(row);
      }
      final alloc = Allocator(p);
      await alloc.insert(
          source: AllocSource.saleReturn, sourceId: returnId, docType: AllocDocType.sale, docId: saleId, amount: applied);
      await p.commit(date: p.now, sourceType: 'sale_return', sourceId: returnId, memo: 'Return on ${sale.invoiceNo}');
      if (!refund && remainder.isPositive) await alloc.settleParty(sale.partyId!);
      await p.audit('sale_return', returnId, 'create', after: {'sale': sale.invoiceNo, 'amount': r.paisa});
      return returnId;
    });
  }

  /// Reverses a whole sale (Undo, or correction with owner PIN). The
  /// invoice keeps its number; a reversal document mirrors it.
  Future<String> reverseSale(String saleId) => posting.run((p) async {
        final sale = await (db.select(db.sales)..where((s) => s.id.equals(saleId))).getSingleOrNull();
        if (sale == null) throw const PostingException(PostingError.notFound);
        if (sale.status != DocStatus.posted) throw const PostingException(PostingError.alreadyReversed);
        final returns = await (db.select(db.saleReturns)
              ..where((r) => r.saleId.equals(saleId) & r.status.equalsValue(DocStatus.posted)))
            .get();
        if (returns.isNotEmpty) throw const PostingException(PostingError.cannotReverse, 'has returns');

        final plan = await (db.select(db.qistPlans)..where((q) => q.saleId.equals(saleId))).getSingleOrNull();
        if (plan != null) {
          if ((await LedgerQueries(db).allocatedTo(plan.id)).isPositive || plan.status == QistPlanStatus.cancelled) {
            throw const PostingException(PostingError.cannotReverse, 'qist has collections');
          }
        }

        final revId = newId();
        await db.into(db.sales).insert(SalesCompanion.insert(
              id: revId,
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              invoiceSeq: sale.invoiceSeq,
              invoiceNo: sale.invoiceNo,
              partyId: Value(sale.partyId),
              date: p.now,
              gross: sale.gross,
              subtotal: sale.subtotal,
              discount: Value(sale.discount),
              tax: Value(sale.tax),
              delivery: Value(sale.delivery),
              markup: Value(sale.markup),
              total: sale.total,
              paid: sale.paid,
              paidMethod: sale.paidMethod,
              due: sale.due,
              paymentMode: sale.paymentMode,
              status: DocStatus.reversal,
              reversesId: Value(sale.id),
              note: const Value('Reversal'),
            ));
        await p.mirrorSource(sourceId: sale.id, reversalId: revId, sourceType: 'sale');

        final items = await (db.select(db.saleItems)..where((x) => x.saleId.equals(saleId))).get();
        for (final i in items.where((i) => i.imeiUnitId != null)) {
          await (db.update(db.imeiUnits)..where((u) => u.id.equals(i.imeiUnitId!))).write(ImeiUnitsCompanion(
            status: const Value(ImeiStatus.inStock),
            saleRefId: const Value(null),
            warrantyUntil: const Value(null),
            updatedAt: Value(p.now),
          ));
        }
        await (db.update(db.sales)..where((s) => s.id.equals(saleId)))
            .write(SalesCompanion(status: const Value(DocStatus.reversed), updatedAt: Value(p.now)));
        if (plan != null) {
          await (db.update(db.qistPlans)..where((q) => q.id.equals(plan.id)))
              .write(QistPlansCompanion(status: const Value(QistPlanStatus.cancelled), updatedAt: Value(p.now)));
        }
        final alloc = Allocator(p);
        await alloc.voidFor(saleId);
        if (sale.partyId != null) await alloc.settleParty(sale.partyId!);
        await p.audit('sale', saleId, 'reverse', before: {'invoice': sale.invoiceNo, 'total': sale.total.paisa});
        return revId;
      });
}

class _Line {
  _Line(this.input, this.product, this.qty, this.unit);

  final SaleLineInput input;
  final Product product;
  final int qty;
  final ImeiUnit? unit;
}

/// Base units per [unitId] for [product] (carton = 24 pcs → 24).
Future<int> unitFactor(AppDatabase db, Product product, String? unitId) async {
  if (unitId == null || unitId == product.unitId) return 1;
  final unit = await (db.select(db.units)..where((u) => u.id.equals(unitId))).getSingleOrNull();
  if (unit == null) throw const PostingException(PostingError.notFound, 'unit');
  if (unit.baseUnitId == null) return 1;
  if (product.unitId != null && unit.baseUnitId != product.unitId) {
    throw const PostingException(PostingError.invalidInput, 'unit does not match product');
  }
  return unit.factor;
}

/// Markup recognised when a qist plan's collected amount goes from
/// [paidBefore] to [paidBefore] + [paidNow] (spec 8.1: A × M / T).
/// Computed cumulatively so the total recognised equals M exactly once the
/// plan is fully paid.
Money markupEarned({required Money markup, required Money total, required Money paidBefore, required Money paidNow}) {
  if (markup.isZero || total.isZero) return Money.zero;
  final after = markup.ratio((paidBefore + paidNow).paisa, total.paisa);
  final before = markup.ratio(paidBefore.paisa, total.paisa);
  return after - before;
}
