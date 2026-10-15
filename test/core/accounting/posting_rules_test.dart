import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/accounting/posting.dart';
import 'package:smart_dukan/core/accounting/system_accounts.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/features/products/application/product_service.dart';
import 'package:smart_dukan/features/purchases/application/purchase_service.dart';
import 'package:smart_dukan/features/sales/application/sale_service.dart';

import '../../helpers/test_shop.dart';

Matcher throwsPosting(PostingError code) =>
    throwsA(isA<PostingException>().having((e) => e.code, 'code', code));

void main() {
  group('Opening balances (8.1)', () {
    test('opening cash, bank and wallet credit OPENING_EQUITY', () async {
      final shop = await TestShop.create();
      await shop.payments.openingBalance(amount: rs(5000));
      await shop.payments.openingBalance(amount: rs(20000), method: PaymentMethod.bank);
      await shop.payments.openingBalance(amount: rs(1500), method: PaymentMethod.jazzcash);
      expect(await shop.bal(SysAccount.cash), rs(5000));
      expect(await shop.bal(SysAccount.bank), rs(20000));
      expect(await shop.bal(SysAccount.wallet), rs(1500));
      expect(await shop.bal(SysAccount.openingEquity), -rs(26500));
      await shop.expectHealthy();
    });

    test('opening stock: Dr Inventory qty × cost, Cr OPENING_EQUITY, dated go-live', () async {
      final shop = await TestShop.create();
      shop.advance(const Duration(days: 3));
      await shop.products.createProduct(ProductInput(name: 'Cable', salePrice: rs(200)),
          openingQty: 12, openingCost: rs(80));
      expect(await shop.bal(SysAccount.inventory), rs(960));
      expect(await shop.bal(SysAccount.openingEquity), -rs(960));
      final entry = (await shop.db.select(shop.db.journalEntries).get()).single;
      expect(entry.date, DateTime(2026, 10, 1));
      await shop.expectHealthy();
    });

    test('customer owes the shop: Dr AR, Cr OPENING_EQUITY; shop owes supplier: Dr OPENING_EQUITY, Cr AP', () async {
      final shop = await TestShop.create();
      final c = await shop.customer('Bilal', opening: rs(1200));
      final s = await shop.supplier('Gul Traders', opening: -rs(4000));
      expect(await shop.party(c), rs(1200));
      expect(await shop.party(s), -rs(4000));
      expect(await shop.bal(SysAccount.ar), rs(1200));
      expect(await shop.bal(SysAccount.ap), -rs(4000));
      expect(await shop.bal(SysAccount.openingEquity), rs(2800));
      await shop.expectHealthy();
    });
  });

  group('Sales', () {
    late TestShop shop;
    late String phone;
    setUp(() async {
      shop = await TestShop.create();
      phone = await shop.products.createProduct(ProductInput(name: 'Earbuds', salePrice: rs(1000)),
          openingQty: 10, openingCost: rs(600));
    });

    test('cash sale: Dr Cash, Cr Sales; COGS at average cost', () async {
      await shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: phone, unitQty: 2, unitPrice: rs(1000))]));
      expect(await shop.bal(SysAccount.cash), rs(2000));
      expect(await shop.bal(SysAccount.sales), -rs(2000));
      expect(await shop.bal(SysAccount.cogs), rs(1200));
      expect((await shop.stock(phone)).qtyOnHand, 8);
      await shop.expectHealthy();
    });

    test('udhaar sale needs a customer and posts all to AR', () async {
      await expectLater(
        () => shop.sales.createSale(SaleInput(
            lines: [SaleLineInput(productId: phone, unitPrice: rs(1000))], mode: SalePaymentMode.udhaar)),
        throwsPosting(PostingError.partyRequired),
      );
      final c = await shop.customer('Kamran');
      await shop.sales.createSale(SaleInput(
          partyId: c, lines: [SaleLineInput(productId: phone, unitPrice: rs(1000))], mode: SalePaymentMode.udhaar));
      expect(await shop.party(c), rs(1000));
      expect(await shop.bal(SysAccount.cash), Money.zero);
      await shop.expectHealthy();
    });

    test('wallet sale posts to WALLET', () async {
      await shop.sales.createSale(SaleInput(
          lines: [SaleLineInput(productId: phone, unitPrice: rs(1000))],
          mode: SalePaymentMode.wallet,
          method: PaymentMethod.easypaisa));
      expect(await shop.bal(SysAccount.wallet), rs(1000));
      await shop.expectHealthy();
    });

    test('invoice discount, line discount, tax and delivery (8.1 invoice extras)', () async {
      final c = await shop.customer('Sana');
      await shop.sales.createSale(SaleInput(
        partyId: c,
        lines: [SaleLineInput(productId: phone, unitQty: 3, unitPrice: rs(1000), discount: rs(100))],
        discount: rs(200),
        tax: rs(150),
        delivery: rs(50),
        mode: SalePaymentMode.mixed,
        paidNow: rs(2000),
      ));
      // total = 3000 − 100 − 200 + 150 + 50 = 2900
      expect(await shop.bal(SysAccount.sales), -rs(3000)); // gross
      expect(await shop.bal(SysAccount.discount), rs(300));
      expect(await shop.bal(SysAccount.salesTaxPayable), -rs(150));
      expect(await shop.bal(SysAccount.deliveryIncome), -rs(50));
      expect(await shop.bal(SysAccount.cash), rs(2000));
      expect(await shop.party(c), rs(900));
      await shop.expectHealthy();
    });

    test('cannot sell more than stock unless negative stock is allowed', () async {
      await expectLater(
        () => shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: phone, unitQty: 11, unitPrice: rs(1))])),
        throwsPosting(PostingError.insufficientStock),
      );
      await shop.expectHealthy();
    });

    test('a failed save writes nothing and does not consume an invoice number', () async {
      await expectLater(
        shop.sales.createSale(SaleInput(lines: [
          SaleLineInput(productId: phone, unitQty: 1, unitPrice: rs(1000)),
          SaleLineInput(productId: phone, unitQty: 50, unitPrice: rs(1000)),
        ])),
        throwsPosting(PostingError.insufficientStock),
      );
      expect(await shop.db.select(shop.db.sales).get(), isEmpty);
      expect((await shop.stock(phone)).qtyOnHand, 10);
      final r = await shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: phone, unitPrice: rs(1000))]));
      expect(r.invoiceNo, 'INV-00001');
      await shop.expectHealthy();
    });

    test('price below min sale price needs owner approval', () async {
      final p = await shop.products.createProduct(
          ProductInput(name: 'Glass', salePrice: rs(300), minSalePrice: rs(250)),
          openingQty: 5,
          openingCost: rs(100));
      await expectLater(
        () => shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: p, unitPrice: rs(200))])),
        throwsPosting(PostingError.belowMinPrice),
      );
      await shop.sales.createSale(
          SaleInput(lines: [SaleLineInput(productId: p, unitPrice: rs(200))], priceOverrideApproved: true));
      await shop.expectHealthy();
    });

    test('invoice numbers are sequential; reversed invoices keep their number', () async {
      final a = await shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: phone, unitPrice: rs(1000))]));
      await shop.sales.reverseSale(a.saleId);
      final b = await shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: phone, unitPrice: rs(1000))]));
      expect(a.invoiceNo, 'INV-00001');
      expect(b.invoiceNo, 'INV-00002');
      final original = await (shop.db.select(shop.db.sales)..where((s) => s.id.equals(a.saleId))).getSingle();
      expect(original.status, DocStatus.reversed);
      await shop.expectHealthy();
    });

    test('sale reversal mirrors journal and stock exactly', () async {
      final c = await shop.customer('Zain');
      final r = await shop.sales.createSale(SaleInput(
          partyId: c,
          lines: [SaleLineInput(productId: phone, unitQty: 2, unitPrice: rs(1000))],
          mode: SalePaymentMode.mixed,
          paidNow: rs(500)));
      await shop.sales.reverseSale(r.saleId);
      expect(await shop.party(c), Money.zero);
      expect(await shop.bal(SysAccount.cash), Money.zero);
      expect(await shop.bal(SysAccount.cogs), Money.zero);
      expect(await shop.bal(SysAccount.sales), Money.zero);
      expect((await shop.stock(phone)).qtyOnHand, 10);
      expect((await shop.stock(phone)).value, rs(6000));
      await expectLater(() => shop.sales.reverseSale(r.saleId), throwsPosting(PostingError.alreadyReversed));
      await shop.expectHealthy();
    });

    test('customer advance (8.1): Dr Cash, Cr AR; next sale uses it up', () async {
      final c = await shop.customer('Usman');
      final pay = await shop.payments.receive(partyId: c, amount: rs(1500));
      expect(await shop.party(c), -rs(1500)); // advance shows as credit
      final s = await shop.sales.createSale(SaleInput(
          partyId: c, lines: [SaleLineInput(productId: phone, unitPrice: rs(1000))], mode: SalePaymentMode.udhaar));
      expect(await shop.party(c), -rs(500));
      final sale = await (shop.db.select(shop.db.sales)..where((x) => x.id.equals(s.saleId))).getSingle();
      expect(await shop.ledger.saleOpenDue(sale), Money.zero);
      expect(await shop.ledger.allocatedFrom(pay), rs(1000));
      await shop.expectHealthy();
    });

    test('carton to piece conversion', () async {
      final pcs = (await (shop.db.select(shop.db.units)..where((u) => u.symbol.equals('pcs'))).getSingle()).id;
      final ctn = (await (shop.db.select(shop.db.units)..where((u) => u.symbol.equals('ctn'))).getSingle()).id;
      final juice = await shop.product('Juice', price: rs(50), unitId: pcs);
      await shop.purchases.createPurchase(PurchaseInput(
          lines: [PurchaseLineInput(productId: juice, unitId: ctn, unitQty: 2, unitCost: rs(960))], paid: rs(1920)));
      expect((await shop.stock(juice)).qtyOnHand, 48);
      expect((await shop.stock(juice)).value, rs(1920)); // Rs 40 a piece
      await shop.sales.createSale(SaleInput(lines: [
        SaleLineInput(productId: juice, unitId: ctn, unitQty: 1, unitPrice: rs(1150)),
        SaleLineInput(productId: juice, unitQty: 3, unitPrice: rs(50)),
      ]));
      expect((await shop.stock(juice)).qtyOnHand, 21);
      expect(await shop.bal(SysAccount.cogs), rs(27 * 40));
      await shop.expectHealthy();
    });
  });

  group('Sale returns (8.1)', () {
    late TestShop shop;
    late String item;
    late String c;
    setUp(() async {
      shop = await TestShop.create();
      item = await shop.products.createProduct(ProductInput(name: 'Cover', salePrice: rs(400)),
          openingQty: 10, openingCost: rs(150));
      c = await shop.customer('Hamza');
    });

    Future<(String, SaleItem)> sell({required SalePaymentMode mode, Money? paid, Money discount = Money.zero}) async {
      final r = await shop.sales.createSale(SaleInput(
          partyId: c,
          lines: [SaleLineInput(productId: item, unitQty: 4, unitPrice: rs(400))],
          discount: discount,
          mode: mode,
          paidNow: paid));
      final si = await (shop.db.select(shop.db.saleItems)..where((x) => x.saleId.equals(r.saleId))).getSingle();
      return (r.saleId, si);
    }

    test('return first reduces what the customer still owes', () async {
      final (sale, si) = await sell(mode: SalePaymentMode.udhaar);
      await shop.sales.returnSale(saleId: sale, lines: [SaleReturnLine(saleItemId: si.id, qty: 1)]);
      expect(await shop.party(c), rs(1200));
      expect(await shop.bal(SysAccount.cash), Money.zero);
      await shop.expectHealthy();
    });

    test('remainder refunded in cash (mixed-payment refund)', () async {
      final (sale, si) = await sell(mode: SalePaymentMode.mixed, paid: rs(1400)); // due 200
      await shop.sales.returnSale(saleId: sale, lines: [SaleReturnLine(saleItemId: si.id, qty: 2)]); // R = 800
      expect(await shop.party(c), Money.zero); // 200 due cleared
      expect(await shop.bal(SysAccount.cash), rs(1400 - 600));
      await shop.expectHealthy();
    });

    test('remainder kept as customer credit', () async {
      final (sale, si) = await sell(mode: SalePaymentMode.cash);
      await shop.sales.returnSale(
          saleId: sale, lines: [SaleReturnLine(saleItemId: si.id, qty: 1)], refundRemainder: false);
      expect(await shop.party(c), -rs(400));
      expect(await shop.bal(SysAccount.cash), rs(1600));
      await shop.expectHealthy();
    });

    test('discount is prorated: R is the net value, COGS reversed at snapshot', () async {
      final (sale, si) = await sell(mode: SalePaymentMode.cash, discount: rs(100)); // net 1500
      await shop.sales.returnSale(saleId: sale, lines: [SaleReturnLine(saleItemId: si.id, qty: 1)]);
      expect(await shop.bal(SysAccount.salesReturns), rs(375));
      expect(await shop.bal(SysAccount.cogs), rs(450));
      expect((await shop.stock(item)).qtyOnHand, 7);
      await shop.expectHealthy();
    });

    test('cannot return more than sold minus earlier returns', () async {
      final (sale, si) = await sell(mode: SalePaymentMode.cash);
      await shop.sales.returnSale(saleId: sale, lines: [SaleReturnLine(saleItemId: si.id, qty: 3)]);
      await expectLater(() => shop.sales.returnSale(saleId: sale, lines: [SaleReturnLine(saleItemId: si.id, qty: 2)]),
          throwsPosting(PostingError.overReturn));
      await shop.sales.returnSale(saleId: sale, lines: [SaleReturnLine(saleItemId: si.id, qty: 1)]);
      // Full return in parts: everything reverses exactly.
      expect(await shop.bal(SysAccount.salesReturns), rs(1600));
      expect(await shop.bal(SysAccount.cogs), Money.zero);
      await expectLater(() => shop.sales.reverseSale(sale), throwsPosting(PostingError.cannotReverse));
      await shop.expectHealthy();
    });

    test('rounding: three partial returns of an odd discount sum exactly', () async {
      final r = await shop.sales.createSale(SaleInput(
          lines: [SaleLineInput(productId: item, unitQty: 3, unitPrice: rs(400))], discount: const Money(100)));
      final si = await (shop.db.select(shop.db.saleItems)..where((x) => x.saleId.equals(r.saleId))).getSingle();
      for (var i = 0; i < 3; i++) {
        await shop.sales.returnSale(saleId: r.saleId, lines: [SaleReturnLine(saleItemId: si.id, qty: 1)]);
      }
      expect(await shop.bal(SysAccount.salesReturns), si.netAmount);
      expect(await shop.bal(SysAccount.cash), Money.zero);
      await shop.expectHealthy();
    });
  });

  group('Purchases and purchase returns (8, 8.1)', () {
    late TestShop shop;
    late String item;
    late String sup;
    setUp(() async {
      shop = await TestShop.create();
      item = await shop.product('Battery');
      sup = await shop.supplier('Karachi Wholesale');
    });

    test('purchase with discount and freight: freight goes into inventory cost', () async {
      await shop.purchases.createPurchase(PurchaseInput(
        partyId: sup,
        lines: [PurchaseLineInput(productId: item, unitQty: 10, unitCost: rs(100))],
        discount: rs(50),
        extraCost: rs(150),
        paid: rs(500),
        method: PaymentMethod.bank,
      ));
      expect(await shop.bal(SysAccount.inventory), rs(1100));
      expect(await shop.bal(SysAccount.bank), -rs(500));
      expect(await shop.party(sup), -rs(600));
      expect((await shop.stock(item)).value.ratio(1, 10), rs(110));
      await shop.expectHealthy();
    });

    test('purchase return reduces the supplier due first, then refund or credit', () async {
      final p = await shop.purchases.createPurchase(PurchaseInput(
          partyId: sup, lines: [PurchaseLineInput(productId: item, unitQty: 10, unitCost: rs(100))], paid: rs(700)));
      final pi = (await shop.db.select(shop.db.purchaseItems).get()).single;
      await shop.purchases.returnPurchase(
          purchaseId: p.purchaseId, lines: [PurchaseReturnLine(purchaseItemId: pi.id, qty: 2)]);
      expect(await shop.party(sup), -rs(100));
      await shop.purchases.returnPurchase(
          purchaseId: p.purchaseId,
          lines: [PurchaseReturnLine(purchaseItemId: pi.id, qty: 3)],
          refundRemainder: false); // 100 against due, 200 kept as credit
      expect(await shop.party(sup), rs(200)); // supplier now owes the shop
      expect((await shop.stock(item)).qtyOnHand, 5);
      await shop.purchases.returnPurchase(
          purchaseId: p.purchaseId, lines: [PurchaseReturnLine(purchaseItemId: pi.id, qty: 1)]); // refund cash
      expect(await shop.bal(SysAccount.cash), -rs(600));
      await shop.expectHealthy();
    });

    test('returning at original cost recomputes average; leftover at zero qty goes to INVENTORY_ADJUSTMENT', () async {
      await shop.products.addOpeningStock(item, qty: 1, unitCost: rs(90));
      final p = await shop.purchases.createPurchase(
          PurchaseInput(lines: [PurchaseLineInput(productId: item, unitQty: 3, unitCost: const Money(10001))], paid: const Money(30003)));
      // Sell 1 at average, leaving 3 units with a value that is not 3 × 100.01
      await shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: item, unitPrice: rs(150))]));
      final pi = (await shop.db.select(shop.db.purchaseItems).get()).single;
      await shop.purchases.returnPurchase(
          purchaseId: p.purchaseId, lines: [PurchaseReturnLine(purchaseItemId: pi.id, qty: 3)]);
      final s = await shop.stock(item);
      expect(s.qtyOnHand, 0);
      expect(s.value, Money.zero);
      expect(await shop.bal(SysAccount.inventoryAdjustment), isNot(Money.zero));
      await shop.expectHealthy();
    });

    test('cannot return more than purchased or more than on hand', () async {
      final p = await shop.purchases.createPurchase(
          PurchaseInput(lines: [PurchaseLineInput(productId: item, unitQty: 2, unitCost: rs(100))], paid: rs(200)));
      final pi = (await shop.db.select(shop.db.purchaseItems).get()).single;
      await expectLater(
          () => shop.purchases.returnPurchase(
              purchaseId: p.purchaseId, lines: [PurchaseReturnLine(purchaseItemId: pi.id, qty: 3)]),
          throwsPosting(PostingError.overReturn));
      await shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: item, unitQty: 2, unitPrice: rs(150))]));
      await expectLater(
          () => shop.purchases.returnPurchase(
              purchaseId: p.purchaseId, lines: [PurchaseReturnLine(purchaseItemId: pi.id, qty: 1)]),
          throwsPosting(PostingError.insufficientStock));
      await shop.expectHealthy();
    });

    test('purchase reversal restores stock and supplier balance', () async {
      final p = await shop.purchases.createPurchase(PurchaseInput(
          partyId: sup, lines: [PurchaseLineInput(productId: item, unitQty: 5, unitCost: rs(100))], paid: rs(100)));
      await shop.purchases.reversePurchase(p.purchaseId);
      expect(await shop.party(sup), Money.zero);
      expect((await shop.stock(item)).qtyOnHand, 0);
      expect(await shop.bal(SysAccount.inventory), Money.zero);
      await shop.expectHealthy();
    });
  });

  group('Payments and allocation (5.7)', () {
    test('received payment is allocated oldest-first; payment made reduces AP', () async {
      final shop = await TestShop.create();
      final item = await shop.products.createProduct(ProductInput(name: 'Pouch', salePrice: rs(100)),
          openingQty: 50, openingCost: rs(40));
      final c = await shop.customer('Faisal');
      final s1 = await shop.sales.createSale(SaleInput(
          partyId: c, lines: [SaleLineInput(productId: item, unitQty: 3, unitPrice: rs(100))], mode: SalePaymentMode.udhaar));
      shop.advance(const Duration(hours: 1));
      final s2 = await shop.sales.createSale(SaleInput(
          partyId: c, lines: [SaleLineInput(productId: item, unitQty: 5, unitPrice: rs(100))], mode: SalePaymentMode.udhaar));
      await shop.payments.receive(partyId: c, amount: rs(400));
      final open = await shop.ledger.openSales(c);
      expect(open, hasLength(1));
      expect(open.single.sale.id, s2.saleId);
      expect(open.single.open, rs(400));
      expect(await shop.party(c), rs(400));

      // Explicit allocation to a chosen invoice.
      final s3 = await shop.sales.createSale(SaleInput(
          partyId: c, lines: [SaleLineInput(productId: item, unitQty: 1, unitPrice: rs(100))], mode: SalePaymentMode.udhaar));
      await shop.payments.receive(partyId: c, amount: rs(100), allocations: {s3.saleId: rs(100)});
      expect((await shop.ledger.openSales(c)).map((e) => e.sale.id), [s2.saleId]);
      expect(s1.invoiceNo, 'INV-00001');

      final sup = await shop.supplier('Rehman', opening: -rs(1000));
      await shop.payments.pay(partyId: sup, amount: rs(600), method: PaymentMethod.jazzcash);
      expect(await shop.party(sup), -rs(400));
      expect(await shop.bal(SysAccount.wallet), -rs(600));
      await shop.expectHealthy();
    });

    test('payment reversal reopens the invoice', () async {
      final shop = await TestShop.create();
      final item = await shop.products.createProduct(ProductInput(name: 'Pouch', salePrice: rs(100)),
          openingQty: 5, openingCost: rs(40));
      final c = await shop.customer('Asad');
      await shop.sales.createSale(SaleInput(
          partyId: c, lines: [SaleLineInput(productId: item, unitQty: 2, unitPrice: rs(100))], mode: SalePaymentMode.udhaar));
      final pay = await shop.payments.receive(partyId: c, amount: rs(200));
      expect(await shop.ledger.openSales(c), isEmpty);
      await shop.payments.reverse(pay);
      expect(await shop.party(c), rs(200));
      expect(await shop.ledger.openSales(c), hasLength(1));
      await shop.expectHealthy();
    });
  });

  group('Expenses, adjustments, cash closing', () {
    test('expense: Dr Expense:category, Cr Cash; reversal', () async {
      final shop = await TestShop.create();
      final rent = await shop.expenseCategory('rent');
      final id = await shop.expenses.create(categoryId: rent, amount: rs(15000));
      expect(await shop.ledger.accountBalance(expenseAccountKey('rent')), rs(15000));
      expect(await shop.bal(SysAccount.cash), -rs(15000));
      await shop.expenses.reverse(id);
      expect(await shop.bal(SysAccount.cash), Money.zero);
      await shop.expectHealthy();
    });

    test('stock loss: Dr STOCK_LOSS, Cr Inventory; gain; count correction; reversal', () async {
      final shop = await TestShop.create();
      final item = await shop.products.createProduct(ProductInput(name: 'Charger', salePrice: rs(500)),
          openingQty: 10, openingCost: rs(300));
      final loss = await shop.products.adjustStock(productId: item, reason: AdjustmentReason.damaged, qty: 2);
      expect(await shop.bal(SysAccount.stockLoss), rs(600));
      await shop.products.adjustStock(productId: item, reason: AdjustmentReason.found, qty: 1);
      expect(await shop.bal(SysAccount.inventoryAdjustment), -rs(300));
      await shop.products.adjustStock(productId: item, reason: AdjustmentReason.countCorrection, countedQty: 7);
      expect((await shop.stock(item)).qtyOnHand, 7);
      await shop.products.reverseAdjustment(loss);
      expect((await shop.stock(item)).qtyOnHand, 9);
      await shop.expectHealthy();
    });

    test('Galla Band: short, over and exact', () async {
      final shop = await TestShop.create();
      await shop.payments.openingBalance(amount: rs(1000));
      await shop.closing.close(counted: rs(950));
      expect(await shop.bal(SysAccount.cashOverShort), rs(50));
      expect(await shop.bal(SysAccount.cash), rs(950));
      await expectLater(() => shop.closing.close(counted: rs(950)), throwsPosting(PostingError.dayAlreadyClosed));

      shop.advance(const Duration(days: 1));
      await shop.closing.close(counted: rs(1000));
      expect(await shop.bal(SysAccount.cashOverShort), Money.zero);

      shop.advance(const Duration(days: 1));
      final entriesBefore = (await shop.db.select(shop.db.journalEntries).get()).length;
      await shop.closing.close(counted: rs(1000));
      expect((await shop.db.select(shop.db.journalEntries).get()).length, entriesBefore);
      expect(await shop.db.select(shop.db.cashClosings).get(), hasLength(3));
      await shop.expectHealthy();
    });

    test('Galla summary splits the day', () async {
      final shop = await TestShop.create();
      await shop.payments.openingBalance(amount: rs(1000));
      shop.advance(const Duration(days: 1));
      final item = await shop.products.createProduct(ProductInput(name: 'Pouch', salePrice: rs(100)),
          openingQty: 5, openingCost: rs(40));
      await shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: item, unitPrice: rs(100))]));
      await shop.expenses.create(categoryId: await shop.expenseCategory('chai_pani'), amount: rs(30));
      final s = await shop.closing.summary();
      expect(s.opening, rs(1000));
      expect(s.cashSales, rs(100));
      expect(s.expenses, rs(30));
      expect(s.expected, rs(1070));
    });
  });
}
