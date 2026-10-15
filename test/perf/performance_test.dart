@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/accounting/health_check.dart';
import 'package:smart_dukan/core/accounting/posting.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/core/db/db_open.dart';
import 'package:smart_dukan/features/onboarding/application/business_setup_service.dart';
import 'package:smart_dukan/features/products/application/product_service.dart';
import 'package:smart_dukan/features/products/data/products_repository.dart';
import 'package:smart_dukan/features/reports/application/reports_service.dart';
import 'package:smart_dukan/features/sales/application/sale_service.dart';

/// Spec Section 9 performance targets, on an encrypted file database:
/// search < 150 ms with 5,000 products, sale save < 300 ms, reports for a
/// year of data (20,000 sales) < 3 s. Desktop timings are indicative; run
/// the same flow on a 3 GB phone for the acceptance check.
///   flutter test test/perf --tags perf
void main() {
  test('5,000 products and 20,000 sales meet the targets', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = await Directory.systemTemp.createTemp('perf');
    addTearDown(() => dir.delete(recursive: true));
    final db = openEncryptedDatabase(File('${dir.path}/perf.db'), 'ab' * 32, background: false);
    addTearDown(db.close);
    final start = DateTime(2025, 10, 15, 9);
    var clock = start;
    final b = await BusinessSetupService(db).createBusiness(name: 'Perf', goLiveDate: DateTime(2025, 10, 1));
    BusinessCtx ctx() => BusinessCtx(businessId: b.id, userId: 'u', clock: () => clock);

    final sw = Stopwatch()..start();
    final ids = <String>[];
    await db.transaction(() async {
      for (var i = 0; i < 5000; i++) {
        ids.add(await ProductService(db, ctx()).createProduct(
          ProductInput(name: 'Item ${i.toString().padLeft(4, '0')} ${['Cable', 'Cover', 'Charger', 'Glass'][i % 4]}', salePrice: Money.rupees(100 + i % 500)),
          openingQty: 100000,
          openingCost: Money.rupees(50 + i % 300),
        ));
      }
    });
    // ignore: avoid_print
    print('5,000 products: ${sw.elapsedMilliseconds} ms');

    final rnd = Random(1);
    sw.reset();
    await db.transaction(() async {
      for (var i = 0; i < 20000; i++) {
        clock = start.add(Duration(minutes: i * 26)); // spread over a year
        await SaleService(db, ctx()).createSale(SaleInput(lines: [
          SaleLineInput(productId: ids[rnd.nextInt(ids.length)], unitQty: 1 + rnd.nextInt(3), unitPrice: Money.rupees(200)),
          SaleLineInput(productId: ids[rnd.nextInt(ids.length)], unitPrice: Money.rupees(150)),
        ]));
      }
    });
    // ignore: avoid_print
    print('20,000 sales: ${sw.elapsedMilliseconds} ms');

    final repo = ProductsRepository(db);
    final searches = <int>[];
    for (final q in ['Charger', 'Item 4', 'glass', 'SKU-0420', 'zzz']) {
      sw.reset();
      await repo.searchForSale(q);
      searches.add(sw.elapsedMilliseconds);
    }
    // ignore: avoid_print
    print('search ms: $searches');
    expect(searches.reduce(max), lessThan(150));

    sw.reset();
    await SaleService(db, ctx()).createSale(SaleInput(lines: [SaleLineInput(productId: ids.first, unitPrice: Money.rupees(200))]));
    final save = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('one sale save: $save ms');
    expect(save, lessThan(300));

    final svc = ReportsService(db);
    const l = ReportLabels(
      date: 'd', salesCount: 'n', total: 't', paid: 'p', udhaar: 'u', grossProfit: 'g', expenses: 'e', item: 'i',
      category: 'c', staff: 's', qtySold: 'q', amount: 'a', cost: 'c', profit: 'p', grossSales: 'gs', returns: 'r',
      discounts: 'd', netSales: 'ns', cogs: 'cg', otherIncome: 'oi', netProfit: 'np', details: 'd', sku: 's', qty: 'q',
      avgCost: 'ac', stockValue: 'sv', saleValue: 'sv', minStock: 'm', customer: 'c', age0: '0', age31: '31', age61: '61',
      age90: '90', other: 'o', supplier: 's', phone: 'p', dena: 'd', count: 'c', opening: 'o', closing: 'c', inflow: 'i',
      outflow: 'o', balance: 'b', invoice: 'i', walkIn: 'w', jobNo: 'j', device: 'd', status: 's', collected: 'c',
      overdue: 'o', nextDue: 'n', expenseCategory: _ec, repairStatus: _rs,
    );
    final from = DateTime(2025, 10, 1), to = DateTime(2026, 11, 1);
    for (final k in [ReportKind.daily, ReportKind.salesByItem, ReportKind.pnl, ReportKind.stockValue, ReportKind.cashBook]) {
      sw.reset();
      final t = await svc.run(k, from, to, l);
      // ignore: avoid_print
      print('report ${k.name}: ${sw.elapsedMilliseconds} ms, ${t.rows.length} rows');
      expect(sw.elapsedMilliseconds, lessThan(3000), reason: k.name);
    }
    sw.reset();
    expect(await HealthCheck(db).run(), isEmpty);
    // ignore: avoid_print
    print('health check: ${sw.elapsedMilliseconds} ms');
  }, timeout: const Timeout(Duration(minutes: 20)));
}

String _ec(String? k, String n) => n;
String _rs(String s) => s;
