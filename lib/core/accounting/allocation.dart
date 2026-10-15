import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/ids.dart';
import 'ledger_queries.dart';
import 'posting.dart';

/// Links money received/paid to the documents it settles (spec 5.7:
/// "allocate to open invoices (auto oldest-first, editable)").
///
/// Allocations never change balances (the journal does that); they only
/// say which invoice is paid, for the open-invoices list and returns.
class Allocator {
  Allocator(this.p) : q = LedgerQueries(p.db);

  final Posting p;
  final LedgerQueries q;

  AppDatabase get db => p.db;

  Future<void> insert({
    required AllocSource source,
    required String sourceId,
    required AllocDocType docType,
    required String docId,
    required Money amount,
  }) async {
    if (!amount.isPositive) return;
    await db.into(db.paymentAllocations).insert(PaymentAllocationsCompanion.insert(
          id: newId(),
          businessId: p.businessId,
          createdAt: p.now,
          updatedAt: p.now,
          createdBy: Value(p.userId),
          sourceType: source,
          paymentId: sourceId,
          docType: docType,
          docId: docId,
          amount: amount,
        ));
  }

  /// Applies explicit allocations from one source. Each amount is capped at
  /// the document's open due; returns the amount actually allocated.
  Future<Money> allocateExplicit({
    required AllocSource source,
    required String sourceId,
    required Money available,
    required Map<String, Money> byDoc,
    required bool sales,
  }) async {
    var left = available;
    for (final entry in byDoc.entries) {
      if (!left.isPositive) break;
      Money open;
      if (sales) {
        final s = await (db.select(db.sales)..where((x) => x.id.equals(entry.key))).getSingle();
        open = await q.saleOpenDue(s);
      } else {
        final pu = await (db.select(db.purchases)..where((x) => x.id.equals(entry.key))).getSingle();
        open = await q.purchaseOpenDue(pu);
      }
      final amt = Money.min(Money.min(entry.value, open), left);
      await insert(
          source: source,
          sourceId: sourceId,
          docType: sales ? AllocDocType.sale : AllocDocType.purchase,
          docId: entry.key,
          amount: amt);
      left -= Money.max(amt, Money.zero);
    }
    return available - left;
  }

  /// Matches every unallocated credit of the party against its open
  /// documents, oldest first on both sides.
  Future<void> settleParty(String partyId) async {
    await _settle(partyId, PaymentDirection.incoming);
    await _settle(partyId, PaymentDirection.outgoing);
  }

  Future<void> _settle(String partyId, PaymentDirection direction) async {
    final credits = await q.unallocatedCredits(partyId, direction);
    if (credits.isEmpty) return;
    final sales = direction == PaymentDirection.incoming;
    final docs = sales
        ? [for (final s in await q.openSales(partyId)) (id: s.sale.id, open: s.open)]
        : [for (final x in await q.openPurchases(partyId)) (id: x.purchase.id, open: x.open)];
    var di = 0;
    var docLeft = docs.isEmpty ? Money.zero : docs.first.open;
    for (final c in credits) {
      var creditLeft = c.amount;
      while (creditLeft.isPositive && di < docs.length) {
        final amt = Money.min(creditLeft, docLeft);
        await insert(
          source: c.source,
          sourceId: c.sourceId,
          docType: sales ? AllocDocType.sale : AllocDocType.purchase,
          docId: docs[di].id,
          amount: amt,
        );
        creditLeft -= amt;
        docLeft -= amt;
        if (docLeft.isZero) {
          di++;
          if (di < docs.length) docLeft = docs[di].open;
        }
      }
      if (di >= docs.length) break;
    }
  }

  /// Voids every allocation made from or to [id] (used by reversals).
  Future<void> voidFor(String id) async {
    await (db.update(db.paymentAllocations)..where((a) => a.paymentId.equals(id) | a.docId.equals(id)))
        .write(PaymentAllocationsCompanion(isVoid: const Value(true), updatedAt: Value(p.now)));
  }
}
