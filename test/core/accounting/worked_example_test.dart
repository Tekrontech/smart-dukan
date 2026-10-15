import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/accounting/system_accounts.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/features/products/application/product_service.dart';
import 'package:smart_dukan/features/purchases/application/purchase_service.dart';
import 'package:smart_dukan/features/sales/application/sale_service.dart';

import '../../helpers/test_shop.dart';

/// Spec Section 8 "Worked example (must pass as an automated test)".
void main() {
  test('Section 8 worked example, end to end', () async {
    final shop = await TestShop.create();

    // 1. Opening: 10 chargers at Rs 300 cost. Inventory = Rs 3,000.
    final charger = await shop.products.createProduct(
      ProductInput(name: 'Charger', salePrice: rs(500)),
      openingQty: 10,
      openingCost: rs(300),
    );
    expect(await shop.bal(SysAccount.inventory), rs(3000));
    expect((await shop.stock(charger)).qtyOnHand, 10);

    // 2. Purchase 10 more at Rs 360, pay Rs 2,000 cash, Rs 1,600 due.
    //    New avg cost = (3,000 + 3,600) / 20 = Rs 330. Supplier = Rs 1,600 Dena.
    final supplier = await shop.supplier('Hall Road Traders');
    await shop.purchases.createPurchase(PurchaseInput(
      partyId: supplier,
      lines: [PurchaseLineInput(productId: charger, unitQty: 10, unitCost: rs(360))],
      paid: rs(2000),
    ));
    final afterPurchase = await shop.stock(charger);
    expect(afterPurchase.qtyOnHand, 20);
    expect(afterPurchase.value, rs(6600));
    expect(afterPurchase.value.ratio(1, afterPurchase.qtyOnHand), rs(330));
    expect(await shop.party(supplier), -rs(1600)); // Dena
    expect(await shop.bal(SysAccount.ap), -rs(1600));

    // 3. Sell 4 chargers at Rs 500 to Ali: total 2,000, pays 1,200 cash,
    //    800 udhaar. COGS = 4 × 330 = 1,320. Gross profit = 680. Stock = 16.
    final ali = await shop.customer('Ali');
    final sale = await shop.sales.createSale(SaleInput(
      partyId: ali,
      lines: [SaleLineInput(productId: charger, unitQty: 4, unitPrice: rs(500))],
      mode: SalePaymentMode.mixed,
      paidNow: rs(1200),
    ));
    expect(sale.total, rs(2000));
    expect(await shop.bal(SysAccount.cogs), rs(1320));
    expect(-(await shop.bal(SysAccount.sales)) - await shop.bal(SysAccount.cogs), rs(680));
    expect((await shop.stock(charger)).qtyOnHand, 16);
    expect(await shop.party(ali), rs(800));

    // 4. Ali pays Rs 300 later. Ali balance = Rs 500 Lena. No new sale.
    await shop.payments.receive(partyId: ali, amount: rs(300));
    expect(await shop.party(ali), rs(500));
    expect(await shop.db.select(shop.db.sales).get(), hasLength(1));

    // 5. Ali returns 1 charger. Sales return Rs 500 reduces Ali to Rs 0;
    //    stock = 17; COGS reversed by Rs 330.
    final item = (await shop.db.select(shop.db.saleItems).get()).single;
    await shop.sales.returnSale(saleId: sale.saleId, lines: [SaleReturnLine(saleItemId: item.id, qty: 1)]);
    expect(await shop.party(ali), Money.zero);
    expect((await shop.stock(charger)).qtyOnHand, 17);
    expect(await shop.bal(SysAccount.cogs), rs(1320 - 330));
    expect(await shop.bal(SysAccount.salesReturns), rs(500));

    // Cash: 2,000 paid to supplier out, 1,200 + 300 in.
    expect(await shop.bal(SysAccount.cash), rs(-2000 + 1200 + 300));

    // 6. Trial balance = 0; stock_balances = Σ stock_movements; party
    //    balances = Σ their journal lines. (All Section 8 invariants.)
    await shop.expectHealthy();
  });
}
