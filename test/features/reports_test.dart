import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/features/products/application/product_service.dart';
import 'package:smart_dukan/features/purchases/application/purchase_service.dart';
import 'package:smart_dukan/features/reports/application/reports_service.dart';
import 'package:smart_dukan/features/sales/application/sale_service.dart';

import '../helpers/test_shop.dart';

const _l = ReportLabels(
  date: 'Date', salesCount: 'n', total: 'Total', paid: 'Paid', udhaar: 'Udhaar', grossProfit: 'GP', expenses: 'Exp',
  item: 'Item', category: 'Cat', staff: 'Staff', qtySold: 'Qty', amount: 'Amt', cost: 'Cost', profit: 'Profit',
  grossSales: 'Gross', returns: 'Returns', discounts: 'Disc', netSales: 'Net', cogs: 'COGS', otherIncome: 'Other',
  netProfit: 'NP', details: 'Details', sku: 'SKU', qty: 'Qty', avgCost: 'Avg', stockValue: 'SV', saleValue: 'Sale',
  minStock: 'Min', customer: 'Cust', age0: '0', age31: '31', age61: '61', age90: '90', other: 'Other', supplier: 'Sup',
  phone: 'Ph', dena: 'Dena', count: 'Cnt', opening: 'Open', closing: 'Close', inflow: 'In', outflow: 'Out',
  balance: 'Bal', invoice: 'Inv', walkIn: 'Walk', jobNo: 'Job', device: 'Dev', status: 'St', collected: 'Col',
  overdue: 'Over', nextDue: 'Next', expenseCategory: _ec, repairStatus: _rs,
);
String _ec(String? k, String n) => n;
String _rs(String s) => s;

void main() {
  test('P&L, daily summary, stock value and dues match the Section 8 worked example', () async {
    final shop = await TestShop.create();
    final charger = await shop.products.createProduct(ProductInput(name: 'Charger', salePrice: rs(500)),
        openingQty: 10, openingCost: rs(300));
    final sup = await shop.supplier('Supplier');
    await shop.purchases.createPurchase(PurchaseInput(
        partyId: sup, lines: [PurchaseLineInput(productId: charger, unitQty: 10, unitCost: rs(360))], paid: rs(2000)));
    final ali = await shop.customer('Ali');
    await shop.sales.createSale(SaleInput(
        partyId: ali,
        lines: [SaleLineInput(productId: charger, unitQty: 4, unitPrice: rs(500))],
        mode: SalePaymentMode.mixed,
        paidNow: rs(1200)));
    final svc = ReportsService(shop.db);
    final from = DateTime(2026, 10, 1), to = DateTime(2026, 10, 2);

    final pnl = await svc.run(ReportKind.pnl, from, to, _l);
    final byLabel = {for (final r in pnl.rows) r[0]: r[1]};
    expect(byLabel['Net'], '2,000');
    expect(byLabel['COGS'], '-1,320');
    expect(byLabel['GP'], '680');
    expect(pnl.totals, ['NP', '680']);

    final daily = await svc.run(ReportKind.daily, from, to, _l);
    expect(daily.rows.single.sublist(1), ['1', '2,000', '1,200', '800', '680', '0']);

    final stock = await svc.run(ReportKind.stockValue, from, to, _l);
    expect(stock.rows.single[2], '16');
    expect(stock.rows.single[4], '5,280'); // 16 × 330

    final dues = await svc.run(ReportKind.supplierDues, from, to, _l);
    expect(dues.rows.single.last, '1,600');
    final ageing = await svc.run(ReportKind.customerAgeing, from, to, _l);
    expect(ageing.rows.single.last, '800');
  });
}
