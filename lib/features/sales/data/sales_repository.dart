import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';

class SaleView {
  const SaleView({required this.sale, required this.items, this.party, required this.returns, required this.returnItems});

  final Sale sale;
  final List<SaleItem> items;
  final Party? party;
  final List<SaleReturn> returns;
  final List<SaleReturnItem> returnItems;

  int returnedQty(String saleItemId) => returnItems
      .where((r) => r.saleItemId == saleItemId && returns.any((x) => x.id == r.returnId && x.status == DocStatus.posted))
      .fold(0, (a, r) => a + r.qty);
}

class SaleListItem {
  const SaleListItem(this.sale, this.partyName);

  final Sale sale;
  final String? partyName;
}

/// Read side for sales.
class SalesRepository {
  SalesRepository(this.db);

  final AppDatabase db;

  Future<SaleView?> load(String id) async {
    final sale = await (db.select(db.sales)..where((s) => s.id.equals(id))).getSingleOrNull();
    if (sale == null) return null;
    final items = await (db.select(db.saleItems)..where((i) => i.saleId.equals(id))).get();
    final party = sale.partyId == null
        ? null
        : await (db.select(db.parties)..where((p) => p.id.equals(sale.partyId!))).getSingleOrNull();
    final returns = await (db.select(db.saleReturns)..where((r) => r.saleId.equals(id))).get();
    final rItems = returns.isEmpty
        ? const <SaleReturnItem>[]
        : await (db.select(db.saleReturnItems)..where((r) => r.returnId.isIn(returns.map((x) => x.id)))).get();
    return SaleView(sale: sale, items: items, party: party, returns: returns, returnItems: rItems);
  }

  Stream<SaleView?> watch(String id) =>
      (db.select(db.sales)..where((s) => s.id.equals(id))).watchSingleOrNull().asyncMap((_) => load(id));

  Selectable<SaleListItem> list({String search = '', DateTime? from, DateTime? to, int limit = 50}) {
    final where = <String>["s.status != 'reversal'"];
    final vars = <Variable>[];
    if (search.trim().isNotEmpty) {
      where.add('(s.invoice_no LIKE ? OR p.name LIKE ?)');
      vars.addAll([Variable.withString('%${search.trim()}%'), Variable.withString('%${search.trim()}%')]);
    }
    if (from != null) {
      where.add('s.date >= ?');
      vars.add(Variable.withDateTime(from));
    }
    if (to != null) {
      where.add('s.date < ?');
      vars.add(Variable.withDateTime(to));
    }
    return db.customSelect(
      'SELECT s.*, p.name AS party_name FROM sales s LEFT JOIN parties p ON p.id = s.party_id '
      'WHERE ${where.join(' AND ')} ORDER BY s.date DESC, s.invoice_seq DESC LIMIT ?',
      variables: [...vars, Variable.withInt(limit)],
      readsFrom: {db.sales, db.parties},
    ).asyncMap((r) async => SaleListItem(await db.sales.mapFromRow(r), r.readNullable<String>('party_name')));
  }
}
