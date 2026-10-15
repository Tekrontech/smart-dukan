import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/accounting/ledger_queries.dart';
import '../../../core/accounting/posting.dart';
import '../../../core/accounting/system_accounts.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';

/// Today's cash movement, as shown on the Galla Band screen (spec 5.8).
class CashDaySummary {
  const CashDaySummary({
    required this.day,
    required this.opening,
    required this.cashSales,
    required this.cashReceived,
    required this.cashPaid,
    required this.expenses,
    required this.other,
    required this.expected,
    this.closing,
  });

  final DateTime day;
  final Money opening;
  final Money cashSales;
  final Money cashReceived;

  /// Cash paid out to suppliers / refunds (positive number).
  final Money cashPaid;

  /// Cash expenses (positive number).
  final Money expenses;

  /// Anything else that moved cash (returns, repairs, qist ...), signed.
  final Money other;
  final Money expected;

  /// Set when the day is already closed.
  final CashClosing? closing;
}

/// Denominations on the note helper (spec 5.8).
const List<int> cashDenominations = [5000, 1000, 500, 100, 50, 20, 10];

/// Galla Band — cash closing (spec 5.8, 8.1).
///
/// D = counted − expected. Short: Dr CASH_OVER_SHORT, Cr Cash |D|.
/// Over: Dr Cash, Cr CASH_OVER_SHORT D. D = 0: no entry.
class CashClosingService {
  CashClosingService(this.db, this.ctx) : posting = PostingService(db, ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  final PostingService posting;

  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<CashDaySummary> summary([DateTime? on]) async {
    final day = dayStart(on ?? ctx.clock());
    final next = DateTime(day.year, day.month, day.day + 1);
    final q = LedgerQueries(db);
    final opening = await q.sysBalance(SysAccount.cash, before: day);

    final rows = await db.customSelect(
      'SELECT je.source_type AS t, SUM(jl.debit) AS d, SUM(jl.credit) AS c FROM journal_lines jl '
      'JOIN accounts a ON a.id = jl.account_id JOIN journal_entries je ON je.id = jl.entry_id '
      "WHERE a.system_key = 'CASH' AND je.date >= ? AND je.date < ? GROUP BY je.source_type",
      variables: [Variable.withDateTime(day), Variable.withDateTime(next)],
      readsFrom: {db.journalLines, db.accounts, db.journalEntries},
    ).get();
    var sales = Money.zero, received = Money.zero, paid = Money.zero, expenses = Money.zero, other = Money.zero;
    for (final r in rows) {
      final dr = Money(r.read<int>('d')), cr = Money(r.read<int>('c'));
      switch (r.read<String>('t')) {
        case 'sale':
          sales += dr - cr;
        case 'payment':
          received += dr;
          paid += cr;
        case 'purchase':
          paid += cr - dr;
        case 'expense':
          expenses += cr - dr;
        default:
          other += dr - cr;
      }
    }
    final closing = await (db.select(db.cashClosings)..where((c) => c.date.equals(day))).getSingleOrNull();
    return CashDaySummary(
      day: day,
      opening: opening,
      cashSales: sales,
      cashReceived: received,
      cashPaid: paid,
      expenses: expenses,
      other: other,
      expected: opening + sales + received - paid - expenses + other,
      closing: closing,
    );
  }

  /// Closes today's galla with the [counted] cash. [denominations] maps
  /// note value (Rs) → count, saved for reference.
  Future<String> close({required Money counted, Map<int, int> denominations = const {}, String? note}) {
    if (counted.isNegative) throw const PostingException(PostingError.invalidAmount);
    return posting.run((p) async {
      final day = dayStart(p.now);
      final existing = await (db.select(db.cashClosings)..where((c) => c.date.equals(day))).getSingleOrNull();
      if (existing != null) throw const PostingException(PostingError.dayAlreadyClosed);
      final s = await summary(p.now);
      // Expected = the cash account balance right now.
      final expected = await LedgerQueries(db).sysBalance(SysAccount.cash);
      final diff = counted - expected;
      final id = newId();
      await db.into(db.cashClosings).insert(CashClosingsCompanion.insert(
            id: id,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            date: day,
            openingCash: s.opening,
            expectedCash: expected,
            countedCash: counted,
            difference: diff,
            denominationsJson: Value(jsonEncode({for (final e in denominations.entries) '${e.key}': e.value})),
            closedBy: Value(p.userId),
            note: Value(note),
          ));
      if (diff.isNegative) {
        p.dr(SysAccount.cashOverShort, -diff);
        p.cr(SysAccount.cash, -diff);
      } else if (diff.isPositive) {
        p.dr(SysAccount.cash, diff);
        p.cr(SysAccount.cashOverShort, diff);
      }
      await p.commit(date: p.now, sourceType: 'cash_closing', sourceId: id, memo: 'Galla Band');
      await p.audit('cash_closing', id, 'create', after: {'expected': expected.paisa, 'counted': counted.paisa});
      return id;
    });
  }

  /// Whether [date] falls on a closed day (documents on it need owner PIN
  /// to reverse).
  Future<bool> isClosed(DateTime date) async {
    final row = await (db.select(db.cashClosings)..where((c) => c.date.equals(dayStart(date)))).getSingleOrNull();
    return row != null;
  }
}
