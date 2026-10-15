import '../db/app_database.dart';

/// One failed invariant.
class HealthIssue {
  const HealthIssue(this.check, this.detail);

  final String check;
  final String detail;

  @override
  String toString() => '$check: $detail';
}

/// Runs every Section 8 invariant against the database. Used by tests and
/// by the hidden Health Check screen. An empty list means all good.
class HealthCheck {
  HealthCheck(this.db);

  final AppDatabase db;

  Future<List<HealthIssue>> run() async {
    final issues = <HealthIssue>[];
    await _trialBalance(issues);
    await _entriesBalanced(issues);
    await _stock(issues);
    await _inventoryMatchesStock(issues);
    await _imei(issues);
    await _invoiceSequence(issues);
    await _partyLines(issues);
    await _allocations(issues);
    return issues;
  }

  Future<void> _trialBalance(List<HealthIssue> out) async {
    final r = await db.customSelect('SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c FROM journal_lines').getSingle();
    final d = r.read<int>('d'), c = r.read<int>('c');
    if (d != c) out.add(HealthIssue('trial_balance', 'debits $d != credits $c'));
  }

  Future<void> _entriesBalanced(List<HealthIssue> out) async {
    final rows = await db.customSelect(
      'SELECT entry_id, SUM(debit) d, SUM(credit) c FROM journal_lines GROUP BY entry_id HAVING SUM(debit) != SUM(credit)',
    ).get();
    for (final r in rows) {
      out.add(HealthIssue('entry_balanced', 'entry ${r.read<String>('entry_id')}'));
    }
    final bad = await db.customSelect(
      'SELECT COUNT(*) n FROM journal_lines WHERE debit < 0 OR credit < 0 OR (debit > 0 AND credit > 0)',
    ).getSingle();
    if (bad.read<int>('n') > 0) out.add(HealthIssue('line_shape', '${bad.read<int>('n')} malformed lines'));
  }

  Future<void> _stock(List<HealthIssue> out) async {
    final rows = await db.customSelect(
      'SELECT b.stock_key k, b.qty_on_hand q, b.value v, '
      'COALESCE((SELECT SUM(m.qty_change) FROM stock_movements m WHERE m.stock_key = b.stock_key), 0) mq, '
      'COALESCE((SELECT SUM(m.value_change) FROM stock_movements m WHERE m.stock_key = b.stock_key), 0) mv '
      'FROM stock_balances b',
    ).get();
    final allowNeg = (await (db.select(db.appSettings)..where((s) => s.key.equals('allow_negative_stock'))).getSingleOrNull())
            ?.value ==
        'true';
    for (final r in rows) {
      final k = r.read<String>('k');
      if (r.read<int>('q') != r.read<int>('mq')) {
        out.add(HealthIssue('stock_qty', '$k balance ${r.read<int>('q')} != movements ${r.read<int>('mq')}'));
      }
      if (r.read<int>('v') != r.read<int>('mv')) {
        out.add(HealthIssue('stock_value', '$k balance ${r.read<int>('v')} != movements ${r.read<int>('mv')}'));
      }
      if (r.read<int>('q') < 0 && !allowNeg) out.add(HealthIssue('stock_negative', '$k is ${r.read<int>('q')}'));
      if (r.read<int>('q') == 0 && r.read<int>('v') != 0) {
        out.add(HealthIssue('stock_zero_value', '$k has value ${r.read<int>('v')} at zero qty'));
      }
    }
    final orphan = await db.customSelect(
      'SELECT COUNT(*) n FROM (SELECT DISTINCT stock_key FROM stock_movements) m '
      'WHERE m.stock_key NOT IN (SELECT stock_key FROM stock_balances)',
    ).getSingle();
    if (orphan.read<int>('n') > 0) out.add(const HealthIssue('stock_orphan', 'movements without a balance row'));
  }

  Future<void> _inventoryMatchesStock(List<HealthIssue> out) async {
    final inv = await db.customSelect(
      'SELECT COALESCE(SUM(jl.debit - jl.credit),0) b FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key = 'INVENTORY'",
    ).getSingle();
    final stock = await db.customSelect('SELECT COALESCE(SUM(value),0) v FROM stock_balances').getSingle();
    if (inv.read<int>('b') != stock.read<int>('v')) {
      out.add(HealthIssue('inventory_account', 'ledger ${inv.read<int>('b')} != stock value ${stock.read<int>('v')}'));
    }
  }

  Future<void> _imei(List<HealthIssue> out) async {
    final dup = await db.customSelect(
      "SELECT imei1, COUNT(*) n FROM imei_units WHERE status IN ('inStock','inRepair') GROUP BY imei1 HAVING COUNT(*) > 1",
    ).get();
    for (final r in dup) {
      out.add(HealthIssue('imei_unique', '${r.read<String>('imei1')} in stock ${r.read<int>('n')} times'));
    }
    final counts = await db.customSelect(
      'SELECT p.id pid, '
      "(SELECT COUNT(*) FROM imei_units u WHERE u.product_id = p.id AND u.status = 'inStock') units, "
      '(SELECT COALESCE(SUM(qty_on_hand),0) FROM stock_balances b WHERE b.product_id = p.id) qty, '
      "(SELECT COALESCE(SUM(cost),0) FROM imei_units u WHERE u.product_id = p.id AND u.status = 'inStock') cost, "
      '(SELECT COALESCE(SUM(value),0) FROM stock_balances b WHERE b.product_id = p.id) val '
      'FROM products p WHERE p.tracks_imei = 1',
    ).get();
    for (final r in counts) {
      if (r.read<int>('units') != r.read<int>('qty')) {
        out.add(HealthIssue('imei_stock', 'product ${r.read<String>('pid')}: ${r.read<int>('units')} units vs qty ${r.read<int>('qty')}'));
      }
      if (r.read<int>('cost') != r.read<int>('val')) {
        out.add(HealthIssue('imei_value', 'product ${r.read<String>('pid')}: unit costs ${r.read<int>('cost')} vs value ${r.read<int>('val')}'));
      }
    }
    final soldTwice = await db.customSelect(
      'SELECT si.imei_unit_id u, COUNT(*) n FROM sale_items si JOIN sales s ON s.id = si.sale_id '
      "WHERE si.imei_unit_id IS NOT NULL AND s.status = 'posted' AND NOT EXISTS "
      "(SELECT 1 FROM sale_return_items ri JOIN sale_returns r ON r.id = ri.return_id WHERE ri.sale_item_id = si.id AND r.status = 'posted') "
      'GROUP BY si.imei_unit_id HAVING COUNT(*) > 1',
    ).get();
    for (final r in soldTwice) {
      out.add(HealthIssue('imei_sold_once', '${r.read<String>('u')} sold ${r.read<int>('n')} times'));
    }
  }

  Future<void> _invoiceSequence(List<HealthIssue> out) async {
    final seqs = await db.customSelect("SELECT invoice_seq s FROM sales WHERE status != 'reversal' ORDER BY invoice_seq").get();
    for (var i = 0; i < seqs.length; i++) {
      if (seqs[i].read<int>('s') != i + 1) {
        out.add(HealthIssue('invoice_sequence', 'expected ${i + 1}, found ${seqs[i].read<int>('s')}'));
        break;
      }
    }
  }

  Future<void> _partyLines(List<HealthIssue> out) async {
    final r = await db.customSelect(
      'SELECT COUNT(*) n FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key IN ('AR','AP') AND jl.party_id IS NULL",
    ).getSingle();
    if (r.read<int>('n') > 0) out.add(HealthIssue('party_lines', '${r.read<int>('n')} AR/AP lines without party'));
  }

  Future<void> _allocations(List<HealthIssue> out) async {
    final over = await db.customSelect(
      'SELECT s.invoice_no n FROM sales s WHERE s.status = \'posted\' AND '
      '(SELECT COALESCE(SUM(amount),0) FROM payment_allocations a WHERE a.doc_id = s.id AND a.is_void = 0) > s.due',
    ).get();
    for (final r in over) {
      out.add(HealthIssue('allocation', 'invoice ${r.read<String>('n')} over-allocated'));
    }
    final overPay = await db.customSelect(
      "SELECT p.id i FROM payments p WHERE p.status = 'posted' AND "
      '(SELECT COALESCE(SUM(amount),0) FROM payment_allocations a WHERE a.payment_id = p.id AND a.is_void = 0) > p.amount',
    ).get();
    for (final r in overPay) {
      out.add(HealthIssue('allocation', 'payment ${r.read<String>('i')} over-allocated'));
    }
  }
}

