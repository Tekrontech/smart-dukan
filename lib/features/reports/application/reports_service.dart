import 'package:drift/drift.dart';

import '../../../core/accounting/ledger_queries.dart';
import '../../../core/db/app_database.dart';
import '../../../core/money/money_format.dart';
import '../../../core/utils/fmt.dart';

enum ReportKind {
  daily,
  salesByItem,
  salesByCategory,
  salesByStaff,
  pnl,
  stockValue,
  lowStock,
  customerAgeing,
  supplierDues,
  expenses,
  cashBook,
  imeiSold,
  repairs,
  qist,
}

extension ReportKindX on ReportKind {
  bool get isPro => this == ReportKind.imeiSold || this == ReportKind.repairs || this == ReportKind.qist;

  /// Reports that ignore the date range (snapshots "as of now").
  bool get isSnapshot =>
      this == ReportKind.stockValue || this == ReportKind.lowStock || this == ReportKind.customerAgeing || this == ReportKind.supplierDues;
}

/// A report ready to show, print or export. Cells are display strings;
/// [numeric] marks right-aligned money/qty columns.
class ReportTable {
  const ReportTable({required this.headers, required this.rows, this.totals, this.numeric = const {}, this.summary = const []});

  final List<String> headers;
  final List<List<String>> rows;
  final List<String>? totals;
  final Set<int> numeric;

  /// Key figures shown above the table (label, value).
  final List<(String, String)> summary;
}

/// Section 5.10 reports. All aggregation happens in SQL, and the database
/// runs on its own background isolate (`NativeDatabase.createInBackground`),
/// so the UI stays smooth on a year of data (spec 6, 9).
///
/// Labels come in through [L] so the service stays free of Flutter.
class ReportsService {
  ReportsService(this.db);

  final AppDatabase db;

  static String m(Money x) => MoneyFormat.format(x, symbol: false);
  static String mi(int paisa) => m(Money(paisa));

  List<Variable> _range(DateTime from, DateTime to) => [Variable.withDateTime(from), Variable.withDateTime(to)];

  Future<ReportTable> run(ReportKind kind, DateTime from, DateTime to, ReportLabels l) => switch (kind) {
        ReportKind.daily => daily(from, to, l),
        ReportKind.salesByItem => salesBy('si.description', from, to, l, l.item),
        ReportKind.salesByCategory => salesBy("COALESCE(c.name, '-')", from, to, l, l.category),
        ReportKind.salesByStaff => salesBy("COALESCE(u.name, '-')", from, to, l, l.staff),
        ReportKind.pnl => pnl(from, to, l),
        ReportKind.stockValue => stockValue(l),
        ReportKind.lowStock => lowStock(l),
        ReportKind.customerAgeing => ageing(l),
        ReportKind.supplierDues => supplierDues(l),
        ReportKind.expenses => expenses(from, to, l),
        ReportKind.cashBook => cashBook(from, to, l),
        ReportKind.imeiSold => imeiSold(from, to, l),
        ReportKind.repairs => repairs(from, to, l),
        ReportKind.qist => qist(l),
      };

  Future<ReportTable> daily(DateTime from, DateTime to, ReportLabels l) async {
    final rows = await db.customSelect(
      "SELECT strftime('%Y-%m-%d', s.date, 'unixepoch', 'localtime') d, COUNT(*) n, SUM(s.total) t, SUM(s.paid) p, SUM(s.due) u, "
      '(SELECT COALESCE(SUM(si.cost_total),0) FROM sale_items si JOIN sales s2 ON s2.id = si.sale_id '
      "  WHERE s2.status = 'posted' AND strftime('%Y-%m-%d', s2.date, 'unixepoch', 'localtime') = strftime('%Y-%m-%d', s.date, 'unixepoch', 'localtime')) c "
      "FROM sales s WHERE s.status = 'posted' AND s.date >= ? AND s.date < ? GROUP BY d ORDER BY d",
      variables: _range(from, to),
    ).get();
    final exp = {
      for (final r in await db.customSelect(
        "SELECT strftime('%Y-%m-%d', date, 'unixepoch', 'localtime') d, SUM(amount) a FROM expenses "
        "WHERE status = 'posted' AND date >= ? AND date < ? GROUP BY d",
        variables: _range(from, to),
      ).get())
        r.read<String>('d'): r.read<int>('a'),
    };
    var tt = 0, tp = 0, tu = 0, tc = 0, te = 0, tn = 0;
    final out = <List<String>>[];
    for (final r in rows) {
      final d = r.read<String>('d');
      final t = r.read<int>('t'), p = r.read<int>('p'), u = r.read<int>('u'), c = r.read<int>('c'), e = exp[d] ?? 0;
      tn += r.read<int>('n');
      tt += t;
      tp += p;
      tu += u;
      tc += c;
      te += e;
      out.add([d, '${r.read<int>('n')}', mi(t), mi(p), mi(u), mi(t - c), mi(e)]);
    }
    return ReportTable(
      headers: [l.date, l.salesCount, l.total, l.paid, l.udhaar, l.grossProfit, l.expenses],
      rows: out,
      totals: [l.total, '$tn', mi(tt), mi(tp), mi(tu), mi(tt - tc), mi(te)],
      numeric: {1, 2, 3, 4, 5, 6},
    );
  }

  Future<ReportTable> salesBy(String groupExpr, DateTime from, DateTime to, ReportLabels l, String firstHeader) async {
    final rows = await db.customSelect(
      'SELECT $groupExpr g, SUM(si.qty) q, SUM(si.net_amount) a, SUM(si.cost_total) c '
      'FROM sale_items si JOIN sales s ON s.id = si.sale_id LEFT JOIN products p ON p.id = si.product_id '
      'LEFT JOIN categories c ON c.id = p.category_id LEFT JOIN users u ON u.id = s.created_by '
      "WHERE s.status = 'posted' AND s.date >= ? AND s.date < ? GROUP BY g ORDER BY a DESC",
      variables: _range(from, to),
    ).get();
    var tq = 0, ta = 0, tc = 0;
    final out = [
      for (final r in rows)
        () {
          final q = r.read<int>('q'), a = r.read<int>('a'), c = r.read<int>('c');
          tq += q;
          ta += a;
          tc += c;
          return [r.read<String>('g'), Fmt.qty(q), mi(a), mi(c), mi(a - c)];
        }(),
    ];
    return ReportTable(
      headers: [firstHeader, l.qtySold, l.amount, l.cost, l.profit],
      rows: out,
      totals: [l.total, Fmt.qty(tq), mi(ta), mi(tc), mi(ta - tc)],
      numeric: {1, 2, 3, 4},
    );
  }

  Future<int> _acct(List<String> keys, DateTime from, DateTime to, {bool creditPositive = true}) async {
    final r = await db.customSelect(
      'SELECT COALESCE(SUM(jl.credit - jl.debit),0) b FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      'JOIN journal_entries je ON je.id = jl.entry_id '
      'WHERE a.system_key IN (${keys.map((_) => '?').join(',')}) AND je.date >= ? AND je.date < ?',
      variables: [for (final k in keys) Variable.withString(k), ..._range(from, to)],
    ).getSingle();
    final v = r.read<int>('b');
    return creditPositive ? v : -v;
  }

  /// Simple profit & loss from the journal (spec 5.10).
  Future<ReportTable> pnl(DateTime from, DateTime to, ReportLabels l) async {
    final gross = await _acct(['SALES'], from, to);
    final returns = await _acct(['SALES_RETURNS'], from, to, creditPositive: false);
    final discounts = await _acct(['DISCOUNT'], from, to, creditPositive: false);
    final net = gross - returns - discounts;
    final cogs = await _acct(['COGS'], from, to, creditPositive: false);
    final other = await _acct(['DELIVERY_INCOME', 'REPAIR_INCOME', 'MARKUP_INCOME'], from, to);
    final expRows = await db.customSelect(
      'SELECT a.name n, SUM(jl.debit - jl.credit) b FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      'JOIN journal_entries je ON je.id = jl.entry_id '
      "WHERE a.type = 'expense' AND a.system_key != 'COGS' AND je.date >= ? AND je.date < ? GROUP BY a.id HAVING b != 0 ORDER BY b DESC",
      variables: _range(from, to),
    ).get();
    final expTotal = expRows.fold<int>(0, (a, r) => a + r.read<int>('b'));
    final rows = <List<String>>[
      [l.grossSales, mi(gross)],
      [l.returns, mi(-returns)],
      [l.discounts, mi(-discounts)],
      [l.netSales, mi(net)],
      [l.cogs, mi(-cogs)],
      [l.grossProfit, mi(net - cogs)],
      [l.otherIncome, mi(other)],
      for (final r in expRows) ['  ${r.read<String>('n')}', mi(-r.read<int>('b'))],
      [l.expenses, mi(-expTotal)],
    ];
    return ReportTable(
      headers: [l.details, l.amount],
      rows: rows,
      totals: [l.netProfit, mi(net - cogs + other - expTotal)],
      numeric: {1},
      summary: [(l.netSales, mi(net)), (l.grossProfit, mi(net - cogs)), (l.netProfit, mi(net - cogs + other - expTotal))],
    );
  }

  Future<ReportTable> stockValue(ReportLabels l) async {
    final rows = await db.customSelect(
      'SELECT p.name n, p.sku s, COALESCE(SUM(b.qty_on_hand),0) q, COALESCE(SUM(b.value),0) v, p.sale_price sp '
      'FROM products p LEFT JOIN stock_balances b ON b.product_id = p.id WHERE p.is_active = 1 '
      'GROUP BY p.id ORDER BY v DESC',
    ).get();
    var tq = 0, tv = 0, ts = 0;
    final out = <List<String>>[];
    for (final r in rows) {
      final q = r.read<int>('q'), v = r.read<int>('v'), sp = r.read<int>('sp');
      tq += q;
      tv += v;
      ts += sp * (q > 0 ? q : 0);
      out.add([r.read<String>('n'), r.read<String>('s'), Fmt.qty(q), mi(q > 0 ? (v / q).round() : 0), mi(v), mi(sp * (q > 0 ? q : 0))]);
    }
    return ReportTable(
      headers: [l.item, l.sku, l.qty, l.avgCost, l.stockValue, l.saleValue],
      rows: out,
      totals: [l.total, '', Fmt.qty(tq), '', mi(tv), mi(ts)],
      numeric: {2, 3, 4, 5},
      summary: [(l.stockValue, mi(tv)), (l.saleValue, mi(ts))],
    );
  }

  Future<ReportTable> lowStock(ReportLabels l) async {
    final rows = await db.customSelect(
      'SELECT * FROM (SELECT p.name n, p.min_stock m, COALESCE(SUM(b.qty_on_hand),0) q FROM products p '
      'LEFT JOIN stock_balances b ON b.product_id = p.id WHERE p.is_active = 1 GROUP BY p.id) WHERE q <= m AND m > 0 ORDER BY q',
    ).get();
    return ReportTable(
      headers: [l.item, l.qty, l.minStock],
      rows: [for (final r in rows) [r.read<String>('n'), Fmt.qty(r.read<int>('q')), Fmt.qty(r.read<int>('m'))]],
      numeric: {1, 2},
    );
  }

  /// Customer dues by invoice age; opening balances and anything not tied to
  /// an open invoice go in "Other".
  Future<ReportTable> ageing(ReportLabels l, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    final q = LedgerQueries(db);
    final parties = await db.customSelect(
      'SELECT p.id i, p.name n, SUM(jl.debit - jl.credit) b FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "JOIN parties p ON p.id = jl.party_id WHERE a.system_key = 'AR' GROUP BY p.id HAVING b > 0 ORDER BY b DESC",
    ).get();
    final totals = List<int>.filled(6, 0);
    final out = <List<String>>[];
    for (final p in parties) {
      final buckets = List<int>.filled(4, 0);
      for (final s in await q.openSales(p.read<String>('i'))) {
        final age = today.difference(s.sale.date).inDays;
        buckets[age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3] += s.open.paisa;
      }
      final bal = p.read<int>('b');
      final other = bal - buckets.fold<int>(0, (a, b) => a + b);
      final row = [...buckets, other, bal];
      for (var i = 0; i < 6; i++) {
        totals[i] += row[i];
      }
      out.add([p.read<String>('n'), ...row.map(mi)]);
    }
    return ReportTable(
      headers: [l.customer, l.age0, l.age31, l.age61, l.age90, l.other, l.total],
      rows: out,
      totals: [l.total, ...totals.map(mi)],
      numeric: {1, 2, 3, 4, 5, 6},
    );
  }

  Future<ReportTable> supplierDues(ReportLabels l) async {
    final rows = await db.customSelect(
      'SELECT p.name n, p.phone ph, SUM(jl.debit - jl.credit) b FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "JOIN parties p ON p.id = jl.party_id WHERE a.system_key IN ('AR','AP') AND p.type IN ('supplier','both') "
      'GROUP BY p.id HAVING b < 0 ORDER BY b',
    ).get();
    final total = rows.fold<int>(0, (a, r) => a - r.read<int>('b'));
    return ReportTable(
      headers: [l.supplier, l.phone, l.dena],
      rows: [for (final r in rows) [r.read<String>('n'), r.readNullable<String>('ph') ?? '', mi(-r.read<int>('b'))]],
      totals: [l.total, '', mi(total)],
      numeric: {2},
    );
  }

  Future<ReportTable> expenses(DateTime from, DateTime to, ReportLabels l) async {
    final rows = await db.customSelect(
      'SELECT c.name n, c.system_key k, COUNT(*) cnt, SUM(e.amount) a FROM expenses e JOIN expense_categories c ON c.id = e.category_id '
      "WHERE e.status = 'posted' AND e.date >= ? AND e.date < ? GROUP BY c.id ORDER BY a DESC",
      variables: _range(from, to),
    ).get();
    final total = rows.fold<int>(0, (a, r) => a + r.read<int>('a'));
    return ReportTable(
      headers: [l.category, l.count, l.amount],
      rows: [for (final r in rows) [l.expenseCategory(r.readNullable<String>('k'), r.read<String>('n')), '${r.read<int>('cnt')}', mi(r.read<int>('a'))]],
      totals: [l.total, '', mi(total)],
      numeric: {1, 2},
    );
  }

  Future<ReportTable> cashBook(DateTime from, DateTime to, ReportLabels l) async {
    final opening = await LedgerQueries(db).accountBalance('CASH', before: from);
    final rows = await db.customSelect(
      'SELECT je.date d, je.memo m, je.source_type t, SUM(jl.debit) i, SUM(jl.credit) o FROM journal_lines jl '
      'JOIN accounts a ON a.id = jl.account_id JOIN journal_entries je ON je.id = jl.entry_id '
      "WHERE a.system_key = 'CASH' AND je.date >= ? AND je.date < ? GROUP BY je.id ORDER BY je.date, je.id",
      variables: _range(from, to),
    ).get();
    var bal = opening.paisa, ti = 0, to2 = 0;
    final out = <List<String>>[
      ['', l.opening, '', '', mi(bal)],
    ];
    for (final r in rows) {
      final i = r.read<int>('i'), o = r.read<int>('o');
      bal += i - o;
      ti += i;
      to2 += o;
      final memo = r.read<String>('m');
      out.add([Fmt.dateTime(r.read<DateTime>('d')), memo.isEmpty ? r.read<String>('t') : memo, i == 0 ? '' : mi(i), o == 0 ? '' : mi(o), mi(bal)]);
    }
    return ReportTable(
      headers: [l.date, l.details, l.inflow, l.outflow, l.balance],
      rows: out,
      totals: [l.closing, '', mi(ti), mi(to2), mi(bal)],
      numeric: {2, 3, 4},
    );
  }

  Future<ReportTable> imeiSold(DateTime from, DateTime to, ReportLabels l) async {
    final rows = await db.customSelect(
      'SELECT s.date d, s.invoice_no inv, si.description p, u.imei1 imei, COALESCE(pt.name, ?) c, si.net_amount a, si.cost_total ct '
      'FROM sale_items si JOIN sales s ON s.id = si.sale_id JOIN imei_units u ON u.id = si.imei_unit_id '
      "LEFT JOIN parties pt ON pt.id = s.party_id WHERE s.status = 'posted' AND s.date >= ? AND s.date < ? ORDER BY s.date DESC",
      variables: [Variable.withString(l.walkIn), ..._range(from, to)],
    ).get();
    return ReportTable(
      headers: [l.date, l.invoice, l.item, 'IMEI', l.customer, l.amount, l.profit],
      rows: [
        for (final r in rows)
          [
            Fmt.date(r.read<DateTime>('d')),
            r.read<String>('inv'),
            r.read<String>('p'),
            r.read<String>('imei'),
            r.read<String>('c'),
            mi(r.read<int>('a')),
            mi(r.read<int>('a') - r.read<int>('ct')),
          ],
      ],
      numeric: {5, 6},
    );
  }

  Future<ReportTable> repairs(DateTime from, DateTime to, ReportLabels l) async {
    final rows = await db.customSelect(
      'SELECT j.id i, j.job_no n, p.name c, j.device_model dm, j.status st, j.final_amount f, j.created_at d FROM repair_jobs j '
      'JOIN parties p ON p.id = j.party_id WHERE j.created_at >= ? AND j.created_at < ? ORDER BY j.created_at DESC',
      variables: _range(from, to),
    ).get();
    final q = LedgerQueries(db);
    final out = <List<String>>[];
    for (final r in rows) {
      out.add([
        r.read<String>('n'),
        Fmt.date(r.read<DateTime>('d')),
        r.read<String>('c'),
        r.read<String>('dm'),
        l.repairStatus(r.read<String>('st')),
        mi(r.read<int>('f')),
        m(await q.refBalance(r.read<String>('i'))),
      ]);
    }
    return ReportTable(headers: [l.jobNo, l.date, l.customer, l.device, l.status, l.total, l.balance], rows: out, numeric: {5, 6});
  }

  Future<ReportTable> qist(ReportLabels l, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    final plans = await db.customSelect(
      'SELECT q.id i, p.name c, q.total t, q.down_payment dp, q.status st FROM qist_plans q JOIN parties p ON p.id = q.party_id '
      "WHERE q.status = 'active' ORDER BY q.created_at",
    ).get();
    final out = <List<String>>[];
    var tCollected = 0, tOut = 0, tOver = 0;
    for (final p in plans) {
      final id = p.read<String>('i');
      final sched = await (db.select(db.qistSchedule)..where((s) => s.planId.equals(id))..orderBy([(s) => OrderingTerm.asc(s.seq)])).get();
      final collected = p.read<int>('dp') + sched.fold<int>(0, (a, s) => a + s.amountPaid.paisa);
      final outstanding = p.read<int>('t') - collected;
      final overdue = sched
          .where((s) => s.dueDate.isBefore(DateTime(today.year, today.month, today.day)) && s.amountPaid < s.amountDue)
          .fold<int>(0, (a, s) => a + (s.amountDue - s.amountPaid).paisa);
      final next = sched.where((s) => s.status != QistRowStatus.paid).firstOrNull;
      tCollected += collected;
      tOut += outstanding;
      tOver += overdue;
      out.add([p.read<String>('c'), mi(p.read<int>('t')), mi(collected), mi(outstanding), mi(overdue), next == null ? '-' : Fmt.date(next.dueDate)]);
    }
    return ReportTable(
      headers: [l.customer, l.total, l.collected, l.balance, l.overdue, l.nextDue],
      rows: out,
      totals: [l.total, '', mi(tCollected), mi(tOut), mi(tOver), ''],
      numeric: {1, 2, 3, 4},
    );
  }
}

/// Localized column names, passed in from the UI.
class ReportLabels {
  const ReportLabels({
    required this.date,
    required this.salesCount,
    required this.total,
    required this.paid,
    required this.udhaar,
    required this.grossProfit,
    required this.expenses,
    required this.item,
    required this.category,
    required this.staff,
    required this.qtySold,
    required this.amount,
    required this.cost,
    required this.profit,
    required this.grossSales,
    required this.returns,
    required this.discounts,
    required this.netSales,
    required this.cogs,
    required this.otherIncome,
    required this.netProfit,
    required this.details,
    required this.sku,
    required this.qty,
    required this.avgCost,
    required this.stockValue,
    required this.saleValue,
    required this.minStock,
    required this.customer,
    required this.age0,
    required this.age31,
    required this.age61,
    required this.age90,
    required this.other,
    required this.supplier,
    required this.phone,
    required this.dena,
    required this.count,
    required this.opening,
    required this.closing,
    required this.inflow,
    required this.outflow,
    required this.balance,
    required this.invoice,
    required this.walkIn,
    required this.jobNo,
    required this.device,
    required this.status,
    required this.collected,
    required this.overdue,
    required this.nextDue,
    required this.expenseCategory,
    required this.repairStatus,
  });

  final String date, salesCount, total, paid, udhaar, grossProfit, expenses, item, category, staff, qtySold, amount,
      cost, profit, grossSales, returns, discounts, netSales, cogs, otherIncome, netProfit, details, sku, qty, avgCost,
      stockValue, saleValue, minStock, customer, age0, age31, age61, age90, other, supplier, phone, dena, count, opening,
      closing, inflow, outflow, balance, invoice, walkIn, jobNo, device, status, collected, overdue, nextDue;
  final String Function(String? key, String name) expenseCategory;
  final String Function(String status) repairStatus;
}
