import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';

class ActivityItem {
  const ActivityItem({required this.date, required this.sourceType, required this.sourceId, required this.memo, required this.amount, required this.reversal});

  final DateTime date;
  final String sourceType;
  final String sourceId;
  final String memo;
  final Money amount;
  final bool reversal;
}

class DashboardStats {
  const DashboardStats({
    required this.todaySales,
    required this.galla,
    required this.lena,
    required this.dena,
    required this.todayProfit,
    required this.lowStock,
    required this.qistDue,
    required this.repairsReady,
    required this.recent,
  });

  final Money todaySales;
  final Money galla;
  final Money lena;
  final Money dena;
  final Money todayProfit;
  final int lowStock;
  final int qistDue;
  final int repairsReady;
  final List<ActivityItem> recent;
}

/// Live numbers for Home — "Aaj ka Hisaab" (spec 5.2). Re-computed whenever
/// any posting table changes.
class DashboardRepository {
  DashboardRepository(this.db);

  final AppDatabase db;

  Stream<DashboardStats> watch(DateTime Function() clock) async* {
    yield await load(clock());
    await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables([
      db.journalLines,
      db.sales,
      db.stockBalances,
      db.repairJobs,
      db.qistSchedule,
      db.products,
    ]))) {
      yield await load(clock());
    }
  }

  Future<int> _int(String sql, [List<Variable> vars = const []]) async =>
      (await db.customSelect(sql, variables: vars).getSingle()).read<int>('n');

  Future<DashboardStats> load(DateTime now) async {
    final day = DateTime(now.year, now.month, now.day);
    final next = day.add(const Duration(days: 1));
    final d = [Variable.withDateTime(day), Variable.withDateTime(next)];

    final todaySales = await _int(
        "SELECT COALESCE(SUM(total),0) n FROM sales WHERE status = 'posted' AND date >= ? AND date < ?", d);
    final todayReturns = await _int(
        "SELECT COALESCE(SUM(amount),0) n FROM sale_returns WHERE status = 'posted' AND date >= ? AND date < ?", d);
    final galla = await _int(
        'SELECT COALESCE(SUM(jl.debit - jl.credit),0) n FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
        "WHERE a.system_key = 'CASH'");
    final balances = await db.customSelect(
      'SELECT SUM(CASE WHEN b > 0 THEN b ELSE 0 END) lena, SUM(CASE WHEN b < 0 THEN -b ELSE 0 END) dena FROM ('
      '  SELECT SUM(jl.debit - jl.credit) b FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "  WHERE a.system_key IN ('AR','AP') GROUP BY jl.party_id)",
    ).getSingle();
    // Estimated gross profit: trading income − COGS, from today's entries.
    final profit = await _int(
      'SELECT COALESCE(SUM(jl.credit - jl.debit),0) n FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      'JOIN journal_entries je ON je.id = jl.entry_id '
      "WHERE a.system_key IN ('SALES','SALES_RETURNS','DISCOUNT','DELIVERY_INCOME','REPAIR_INCOME','MARKUP_INCOME','COGS') "
      'AND je.date >= ? AND je.date < ?',
      d,
    );
    final low = await _int(
      'SELECT COUNT(*) n FROM (SELECT p.id, p.min_stock m, COALESCE(SUM(b.qty_on_hand),0) q FROM products p '
      'LEFT JOIN stock_balances b ON b.product_id = p.id WHERE p.is_active = 1 GROUP BY p.id) WHERE q <= m AND m > 0',
    );
    final qist = await _int(
      "SELECT COUNT(*) n FROM qist_schedule s JOIN qist_plans p ON p.id = s.plan_id WHERE p.status = 'active' "
      "AND s.status != 'paid' AND s.due_date < ?",
      [Variable.withDateTime(next)],
    );
    final repairs = await _int("SELECT COUNT(*) n FROM repair_jobs WHERE status = 'ready'");

    final recentRows = await db.customSelect(
      'SELECT je.date d, je.source_type t, je.source_id s, je.memo m, je.reverses_id r, '
      '(SELECT SUM(debit) FROM journal_lines WHERE entry_id = je.id) amt FROM journal_entries je '
      'ORDER BY je.date DESC, je.id DESC LIMIT 10',
    ).get();

    return DashboardStats(
      todaySales: Money(todaySales - todayReturns),
      galla: Money(galla),
      lena: Money(balances.readNullable<int>('lena') ?? 0),
      dena: Money(balances.readNullable<int>('dena') ?? 0),
      todayProfit: Money(profit),
      lowStock: low,
      qistDue: qist,
      repairsReady: repairs,
      recent: [
        for (final r in recentRows)
          ActivityItem(
            date: r.read<DateTime>('d'),
            sourceType: r.read<String>('t'),
            sourceId: r.read<String>('s'),
            memo: r.read<String>('m'),
            amount: Money(r.readNullable<int>('amt') ?? 0),
            reversal: r.readNullable<String>('r') != null,
          ),
      ],
    );
  }
}
