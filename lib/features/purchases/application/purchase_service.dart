import 'package:drift/drift.dart';

import '../../../core/accounting/allocation.dart';
import '../../../core/accounting/ledger_queries.dart';
import '../../../core/accounting/posting.dart';
import '../../../core/accounting/system_accounts.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';
import '../../products/application/product_service.dart';
import '../../sales/application/sale_service.dart' show unitFactor;

class PurchaseLineInput {
  const PurchaseLineInput({
    required this.productId,
    this.variantId,
    this.unitId,
    this.unitQty = 1,
    required this.unitCost,
    this.imeis = const [],
  });

  final String productId;
  final String? variantId;
  final String? unitId;
  final int unitQty;

  /// Cost per [unitId] as on the supplier bill.
  final Money unitCost;

  /// One entry per unit for IMEI-tracked products.
  final List<ImeiInput> imeis;

  Money get lineTotal => unitCost.times(unitQty);
}

class PurchaseInput {
  const PurchaseInput({
    this.partyId,
    required this.lines,
    this.discount = Money.zero,
    this.extraCost = Money.zero,
    required this.paid,
    this.method = PaymentMethod.cash,
    this.supplierBillNo,
    this.billPhotoPath,
    this.note,
  });

  final String? partyId;
  final List<PurchaseLineInput> lines;
  final Money discount;

  /// Freight / purchase tax paid to the supplier — added to inventory cost
  /// (spec 8.1, no input-tax claim in V1).
  final Money extraCost;
  final Money paid;
  final PaymentMethod method;
  final String? supplierBillNo;
  final String? billPhotoPath;
  final String? note;
}

class PurchaseReturnLine {
  const PurchaseReturnLine({required this.purchaseItemId, this.qty = 0, this.imeiUnitIds = const []});

  final String purchaseItemId;

  /// Base units returned (ignored for IMEI lines; use [imeiUnitIds]).
  final int qty;
  final List<String> imeiUnitIds;
}

/// Purchases, purchase returns and reversal (spec 5.4, 8, 8.1).
///
/// Purchase: Dr Inventory (total), Cr Cash/Bank (paid) + AP party (due);
/// stock + qty with the average cost recomputed.
class PurchaseService {
  PurchaseService(this.db, this.ctx) : posting = PostingService(db, ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  final PostingService posting;

  Future<({String purchaseId, String billNo})> createPurchase(PurchaseInput input) => posting.run((p) async {
        if (input.lines.isEmpty) throw const PostingException(PostingError.emptyDocument);
        if (input.discount.isNegative || input.extraCost.isNegative || input.paid.isNegative) {
          throw const PostingException(PostingError.invalidAmount);
        }
        final products = <Product>[];
        final qtys = <int>[];
        for (final l in input.lines) {
          if (l.unitQty <= 0 || l.unitCost.isNegative) throw const PostingException(PostingError.invalidInput);
          final product = await (db.select(db.products)..where((x) => x.id.equals(l.productId))).getSingleOrNull();
          if (product == null) throw const PostingException(PostingError.notFound, 'product');
          final qty = l.unitQty * await unitFactor(db, product, l.unitId);
          if (product.tracksImei && l.imeis.length != qty) throw const PostingException(PostingError.imeiRequired);
          products.add(product);
          qtys.add(qty);
        }
        final subtotal = Money.sum(input.lines.map((l) => l.lineTotal));
        if (input.discount > subtotal) throw const PostingException(PostingError.invalidAmount, 'discount');
        final total = subtotal - input.discount + input.extraCost;
        if (input.paid > total) throw const PostingException(PostingError.overpayment);
        final due = total - input.paid;
        if (due.isPositive && input.partyId == null) throw const PostingException(PostingError.partyRequired);

        final weights = [for (final l in input.lines) l.lineTotal.paisa];
        final discShares = input.discount.allocate(weights);
        final extraShares = input.extraCost.allocate(weights);

        final seq = await p.nextSeq('purchase');
        final billNo = docNumber('PUR-', seq);
        final id = newId();
        await db.into(db.purchases).insert(PurchasesCompanion.insert(
              id: id,
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              billSeq: seq,
              billNo: billNo,
              supplierBillNo: Value(input.supplierBillNo),
              partyId: Value(input.partyId),
              date: p.now,
              subtotal: subtotal,
              discount: Value(input.discount),
              extraCost: Value(input.extraCost),
              total: total,
              paid: input.paid,
              paidMethod: input.method,
              due: due,
              status: DocStatus.posted,
              billPhotoPath: Value(input.billPhotoPath),
              note: Value(input.note),
            ));

        for (var i = 0; i < input.lines.length; i++) {
          final l = input.lines[i];
          final product = products[i];
          final net = l.lineTotal - discShares[i] + extraShares[i];
          if (product.tracksImei) {
            final costs = net.split(l.imeis.length);
            for (var k = 0; k < l.imeis.length; k++) {
              final unitId = await insertImeiUnit(p, product.id, l.variantId, l.imeis[k], costs[k], 'purchase', id);
              await p.stockIn(
                productId: product.id,
                variantId: l.variantId,
                qty: 1,
                value: costs[k],
                type: StockMoveType.purchase,
                refType: 'purchase',
                refId: id,
                imeiUnitId: unitId,
              );
            }
          } else {
            await p.stockIn(
              productId: product.id,
              variantId: l.variantId,
              qty: qtys[i],
              value: net,
              type: StockMoveType.purchase,
              refType: 'purchase',
              refId: id,
            );
          }
          await db.into(db.purchaseItems).insert(PurchaseItemsCompanion.insert(
                id: newId(),
                businessId: p.businessId,
                createdAt: p.now,
                updatedAt: p.now,
                createdBy: Value(p.userId),
                purchaseId: id,
                productId: product.id,
                variantId: Value(l.variantId),
                description: product.name,
                unitId: Value(l.unitId),
                unitQty: l.unitQty,
                qty: qtys[i],
                unitCost: l.unitCost,
                lineTotal: l.lineTotal,
                netCost: net,
              ));
        }

        p.cr(SysAccount.forMethod(input.method), input.paid);
        p.cr(SysAccount.ap, due, partyId: input.partyId);
        await p.commit(date: p.now, sourceType: 'purchase', sourceId: id, memo: 'Purchase $billNo');
        if (input.partyId != null && due.isPositive) await Allocator(p).settleParty(input.partyId!);
        await p.audit('purchase', id, 'create', after: {'bill': billNo, 'total': total.paisa});
        return (purchaseId: id, billNo: billNo);
      });

  Future<Map<String, ({int qty, Money amount})>> returnedSoFar(String purchaseId) async {
    final rows = await db.customSelect(
      'SELECT ri.purchase_item_id AS id, SUM(ri.qty) AS q, SUM(ri.amount) AS a FROM purchase_return_items ri '
      'JOIN purchase_returns r ON r.id = ri.return_id '
      "WHERE r.purchase_id = ? AND r.status = 'posted' GROUP BY ri.purchase_item_id",
      variables: [Variable.withString(purchaseId)],
      readsFrom: {db.purchaseReturnItems, db.purchaseReturns},
    ).get();
    return {for (final r in rows) r.read<String>('id'): (qty: r.read<int>('q'), amount: Money(r.read<int>('a')))};
  }

  /// Purchase return (spec 8.1). R = returned qty × original line unit
  /// cost; first reduces what the shop owes on the bill, then is refunded
  /// or kept as supplier credit.
  Future<String> returnPurchase({
    required String purchaseId,
    required List<PurchaseReturnLine> lines,
    bool refundRemainder = true,
    PaymentMethod refundMethod = PaymentMethod.cash,
    String? note,
  }) =>
      posting.run((p) async {
        final pur = await (db.select(db.purchases)..where((x) => x.id.equals(purchaseId))).getSingleOrNull();
        if (pur == null) throw const PostingException(PostingError.notFound);
        if (pur.status != DocStatus.posted) throw const PostingException(PostingError.alreadyReversed);
        final items = {
          for (final i in await (db.select(db.purchaseItems)..where((x) => x.purchaseId.equals(purchaseId))).get())
            i.id: i
        };
        final before = await returnedSoFar(purchaseId);
        final returnId = newId();
        final seq = await p.nextSeq('purchase_return');
        var total = Money.zero;
        final rows = <PurchaseReturnItemsCompanion>[];

        for (final l in lines) {
          final item = items[l.purchaseItemId];
          if (item == null) throw const PostingException(PostingError.notFound, 'purchase item');
          final product = await (db.select(db.products)..where((x) => x.id.equals(item.productId))).getSingle();
          final done = before[item.id];
          if (product.tracksImei) {
            for (final unitId in l.imeiUnitIds) {
              final unit = await (db.select(db.imeiUnits)..where((u) => u.id.equals(unitId))).getSingleOrNull();
              if (unit == null ||
                  unit.status != ImeiStatus.inStock ||
                  unit.purchaseRefId != purchaseId ||
                  unit.productId != item.productId) {
                throw const PostingException(PostingError.imeiNotAvailable);
              }
              await p.stockOut(
                productId: item.productId,
                variantId: item.variantId,
                qty: 1,
                value: unit.cost,
                type: StockMoveType.purchaseReturn,
                refType: 'purchase_return',
                refId: returnId,
                imeiUnitId: unit.id,
                allowNegative: false,
              );
              await (db.update(db.imeiUnits)..where((u) => u.id.equals(unit.id)))
                  .write(ImeiUnitsCompanion(status: const Value(ImeiStatus.returned), updatedAt: Value(p.now)));
              total += unit.cost;
              rows.add(_item(p, returnId, item, 1, unit.cost, unit.id));
            }
          } else {
            if (l.qty <= 0) continue;
            final doneQty = done?.qty ?? 0;
            if (l.qty > item.qty - doneQty) throw const PostingException(PostingError.overReturn);
            final last = doneQty + l.qty == item.qty;
            final r = last ? item.netCost - (done?.amount ?? Money.zero) : item.netCost.ratio(l.qty, item.qty);
            // Cannot return more than is on hand (spec 8.1).
            await p.stockOut(
              productId: item.productId,
              variantId: item.variantId,
              qty: l.qty,
              value: r,
              type: StockMoveType.purchaseReturn,
              refType: 'purchase_return',
              refId: returnId,
              allowNegative: false,
            );
            total += r;
            rows.add(_item(p, returnId, item, l.qty, r, null));
          }
        }
        if (rows.isEmpty) throw const PostingException(PostingError.emptyDocument);

        final openDue = await LedgerQueries(db).purchaseOpenDue(pur);
        final applied = Money.min(total, Money.max(openDue, Money.zero));
        final remainder = total - applied;
        final refund = pur.partyId == null || refundRemainder;
        p.dr(SysAccount.ap, applied, partyId: pur.partyId);
        if (refund) {
          p.dr(SysAccount.forMethod(refundMethod), remainder);
        } else {
          p.dr(SysAccount.ap, remainder, partyId: pur.partyId);
        }

        await db.into(db.purchaseReturns).insert(PurchaseReturnsCompanion.insert(
              id: returnId,
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              returnSeq: seq,
              returnNo: docNumber('PR-', seq),
              purchaseId: purchaseId,
              partyId: Value(pur.partyId),
              date: p.now,
              amount: total,
              appliedToDue: applied,
              refunded: refund ? remainder : Money.zero,
              refundMethod: Value(refund && remainder.isPositive ? refundMethod : null),
              keptAsCredit: refund ? Money.zero : remainder,
              status: DocStatus.posted,
              note: Value(note),
            ));
        for (final row in rows) {
          await db.into(db.purchaseReturnItems).insert(row);
        }
        final alloc = Allocator(p);
        await alloc.insert(
            source: AllocSource.purchaseReturn,
            sourceId: returnId,
            docType: AllocDocType.purchase,
            docId: purchaseId,
            amount: applied);
        await p.commit(date: p.now, sourceType: 'purchase_return', sourceId: returnId, memo: 'Return on ${pur.billNo}');
        if (!refund && remainder.isPositive) await alloc.settleParty(pur.partyId!);
        await p.audit('purchase_return', returnId, 'create', after: {'bill': pur.billNo, 'amount': total.paisa});
        return returnId;
      });

  PurchaseReturnItemsCompanion _item(Posting p, String returnId, PurchaseItem item, int qty, Money amount, String? imei) =>
      PurchaseReturnItemsCompanion.insert(
        id: newId(),
        businessId: p.businessId,
        createdAt: p.now,
        updatedAt: p.now,
        createdBy: Value(p.userId),
        returnId: returnId,
        purchaseItemId: item.id,
        productId: item.productId,
        variantId: Value(item.variantId),
        imeiUnitId: Value(imei),
        qty: qty,
        amount: amount,
      );

  /// Reverses a purchase. Refused when its stock has already been sold or
  /// returned (the stock would go negative / IMEIs are gone).
  Future<String> reversePurchase(String purchaseId) => posting.run((p) async {
        final pur = await (db.select(db.purchases)..where((x) => x.id.equals(purchaseId))).getSingleOrNull();
        if (pur == null) throw const PostingException(PostingError.notFound);
        if (pur.status != DocStatus.posted) throw const PostingException(PostingError.alreadyReversed);
        final returns = await (db.select(db.purchaseReturns)
              ..where((r) => r.purchaseId.equals(purchaseId) & r.status.equalsValue(DocStatus.posted)))
            .get();
        if (returns.isNotEmpty) throw const PostingException(PostingError.cannotReverse, 'has returns');
        final units = await (db.select(db.imeiUnits)
              ..where((u) => u.purchaseRefId.equals(purchaseId) & u.purchaseRefType.equals('purchase')))
            .get();
        if (units.any((u) => u.status != ImeiStatus.inStock)) {
          throw const PostingException(PostingError.cannotReverse, 'IMEI already sold');
        }
        final items = await (db.select(db.purchaseItems)..where((x) => x.purchaseId.equals(purchaseId))).get();
        for (final i in items) {
          final bal = await p.stockBalance(i.productId, i.variantId);
          if (bal.qtyOnHand < i.qty) throw const PostingException(PostingError.insufficientStock);
        }

        final revId = newId();
        await db.into(db.purchases).insert(PurchasesCompanion.insert(
              id: revId,
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              billSeq: pur.billSeq,
              billNo: pur.billNo,
              partyId: Value(pur.partyId),
              date: p.now,
              subtotal: pur.subtotal,
              discount: Value(pur.discount),
              extraCost: Value(pur.extraCost),
              total: pur.total,
              paid: pur.paid,
              paidMethod: pur.paidMethod,
              due: pur.due,
              status: DocStatus.reversal,
              reversesId: Value(pur.id),
              note: const Value('Reversal'),
            ));
        await p.mirrorSource(sourceId: pur.id, reversalId: revId, sourceType: 'purchase');
        for (final u in units) {
          await (db.update(db.imeiUnits)..where((x) => x.id.equals(u.id)))
              .write(ImeiUnitsCompanion(status: const Value(ImeiStatus.returned), updatedAt: Value(p.now)));
        }
        await (db.update(db.purchases)..where((x) => x.id.equals(pur.id)))
            .write(PurchasesCompanion(status: const Value(DocStatus.reversed), updatedAt: Value(p.now)));
        final alloc = Allocator(p);
        await alloc.voidFor(pur.id);
        if (pur.partyId != null) await alloc.settleParty(pur.partyId!);
        await p.audit('purchase', pur.id, 'reverse');
        return revId;
      });
}
