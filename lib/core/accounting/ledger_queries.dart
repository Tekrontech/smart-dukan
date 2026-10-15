import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'system_accounts.dart';

/// Read-only balance queries over the journal. Every number the app shows
/// for money owed or held comes from here (spec Section 8: party balance
/// shown on screen = Σ (debit − credit) of its AR/AP lines).
class LedgerQueries {
  LedgerQueries(this.db);

  final AppDatabase db;

  /// Debit-minus-credit balance of an account, optionally up to (excluding)
  /// [before] by entry date.
  Future<Money> accountBalance(String key, {DateTime? before, DateTime? from}) async {
    final rows = await db.customSelect(
      'SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS b FROM journal_lines jl '
      'JOIN accounts a ON a.id = jl.account_id '
      'JOIN journal_entries je ON je.id = jl.entry_id '
      'WHERE a.system_key = ?'
      '${before != null ? ' AND je.date < ?' : ''}'
      '${from != null ? ' AND je.date >= ?' : ''}',
      variables: [
        Variable.withString(key),
        if (before != null) Variable.withDateTime(before),
        if (from != null) Variable.withDateTime(from),
      ],
      readsFrom: {db.journalLines, db.accounts, db.journalEntries},
    ).getSingle();
    return Money(rows.read<int>('b'));
  }

  Future<Money> sysBalance(SysAccount a, {DateTime? before, DateTime? from}) =>
      accountBalance(a.key, before: before, from: from);

  /// Signed party balance: positive = Lena (they owe the shop),
  /// negative = Dena (shop owes them, or customer advance).
  Future<Money> partyBalance(String partyId) async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS b FROM journal_lines jl '
      'JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key IN ('AR', 'AP') AND jl.party_id = ?",
      variables: [Variable.withString(partyId)],
      readsFrom: {db.journalLines, db.accounts},
    ).getSingle();
    return Money(row.read<int>('b'));
  }

  /// All party balances, keyed by party id.
  Selectable<({String partyId, Money balance})> watchPartyBalances() {
    return db.customSelect(
      'SELECT jl.party_id AS p, SUM(jl.debit - jl.credit) AS b FROM journal_lines jl '
      'JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key IN ('AR', 'AP') AND jl.party_id IS NOT NULL GROUP BY jl.party_id",
      readsFrom: {db.journalLines, db.accounts},
    ).map((r) => (partyId: r.read<String>('p'), balance: Money(r.read<int>('b'))));
  }

  /// Outstanding AR/AP linked to a document such as a repair job or qist
  /// plan (lines carrying ref_id).
  Future<Money> refBalance(String refId) async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS b FROM journal_lines jl '
      'JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key IN ('AR', 'AP') AND jl.ref_id = ?",
      variables: [Variable.withString(refId)],
      readsFrom: {db.journalLines, db.accounts},
    ).getSingle();
    return Money(row.read<int>('b'));
  }

  /// Sum of non-void allocations against a document.
  Future<Money> allocatedTo(String docId) async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS s FROM payment_allocations WHERE doc_id = ? AND is_void = 0',
      variables: [Variable.withString(docId)],
      readsFrom: {db.paymentAllocations},
    ).getSingle();
    return Money(row.read<int>('s'));
  }

  /// Sum of non-void allocations made from a payment or return.
  Future<Money> allocatedFrom(String sourceId) async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS s FROM payment_allocations WHERE payment_id = ? AND is_void = 0',
      variables: [Variable.withString(sourceId)],
      readsFrom: {db.paymentAllocations},
    ).getSingle();
    return Money(row.read<int>('s'));
  }

  /// Remaining due on a sale (not qist; those are tracked by schedule).
  Future<Money> saleOpenDue(Sale s) async {
    if (s.status != DocStatus.posted || s.paymentMode == SalePaymentMode.qist) return Money.zero;
    return s.due - await allocatedTo(s.id);
  }

  Future<Money> purchaseOpenDue(Purchase p) async {
    if (p.status != DocStatus.posted) return Money.zero;
    return p.due - await allocatedTo(p.id);
  }

  /// Open (partly unpaid) sales of a customer, oldest first.
  Future<List<({Sale sale, Money open})>> openSales(String partyId) async {
    final sales = await (db.select(db.sales)
          ..where((s) =>
              s.partyId.equals(partyId) &
              s.status.equalsValue(DocStatus.posted) &
              s.paymentMode.equalsValue(SalePaymentMode.qist).not())
          ..orderBy([(s) => OrderingTerm.asc(s.date), (s) => OrderingTerm.asc(s.invoiceSeq)]))
        .get();
    final out = <({Sale sale, Money open})>[];
    for (final s in sales) {
      final open = await saleOpenDue(s);
      if (open.isPositive) out.add((sale: s, open: open));
    }
    return out;
  }

  Future<List<({Purchase purchase, Money open})>> openPurchases(String partyId) async {
    final rows = await (db.select(db.purchases)
          ..where((p) => p.partyId.equals(partyId) & p.status.equalsValue(DocStatus.posted))
          ..orderBy([(p) => OrderingTerm.asc(p.date), (p) => OrderingTerm.asc(p.billSeq)]))
        .get();
    final out = <({Purchase purchase, Money open})>[];
    for (final p in rows) {
      final open = await purchaseOpenDue(p);
      if (open.isPositive) out.add((purchase: p, open: open));
    }
    return out;
  }

  /// Unallocated money a party has given (customer advances) or the shop
  /// has paid ahead (supplier credit), oldest first. Includes return
  /// amounts kept as credit.
  Future<List<({String sourceId, AllocSource source, Money amount})>> unallocatedCredits(
      String partyId, PaymentDirection direction) async {
    final out = <({String sourceId, AllocSource source, Money amount})>[];
    final payments = await (db.select(db.payments)
          ..where((p) =>
              p.partyId.equals(partyId) &
              p.direction.equalsValue(direction) &
              p.status.equalsValue(DocStatus.posted) &
              p.refType.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.date), (p) => OrderingTerm.asc(p.id)]))
        .get();
    for (final p in payments) {
      final left = p.amount - await allocatedFrom(p.id);
      if (left.isPositive) out.add((sourceId: p.id, source: AllocSource.payment, amount: left));
    }
    if (direction == PaymentDirection.incoming) {
      final returns = await (db.select(db.saleReturns)
            ..where((r) => r.partyId.equals(partyId) & r.status.equalsValue(DocStatus.posted))
            ..orderBy([(r) => OrderingTerm.asc(r.date)]))
          .get();
      for (final r in returns) {
        final left = r.keptAsCredit - (await allocatedFrom(r.id) - r.appliedToDue);
        if (left.isPositive) out.add((sourceId: r.id, source: AllocSource.saleReturn, amount: left));
      }
    } else {
      final returns = await (db.select(db.purchaseReturns)
            ..where((r) => r.partyId.equals(partyId) & r.status.equalsValue(DocStatus.posted))
            ..orderBy([(r) => OrderingTerm.asc(r.date)]))
          .get();
      for (final r in returns) {
        final left = r.keptAsCredit - (await allocatedFrom(r.id) - r.appliedToDue);
        if (left.isPositive) out.add((sourceId: r.id, source: AllocSource.purchaseReturn, amount: left));
      }
    }
    return out;
  }
}
