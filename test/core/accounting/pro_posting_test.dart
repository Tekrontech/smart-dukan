import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/accounting/posting.dart';
import 'package:smart_dukan/core/accounting/system_accounts.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/features/pro_mobile/qist/application/qist_schedule_sync.dart';
import 'package:smart_dukan/features/products/application/product_service.dart';
import 'package:smart_dukan/features/purchases/application/purchase_service.dart';
import 'package:smart_dukan/features/sales/application/sale_service.dart';

import '../../helpers/test_shop.dart';

Matcher throwsPosting(PostingError code) =>
    throwsA(isA<PostingException>().having((e) => e.code, 'code', code));

void main() {
  group('IMEI', () {
    late TestShop shop;
    late String phone;
    setUp(() async {
      shop = await TestShop.create();
      phone = await shop.product('Galaxy A15', price: rs(45000), imei: true);
    });

    Future<List<ImeiUnit>> units() => shop.db.select(shop.db.imeiUnits).get();

    test('purchase creates units at their own cost; sale uses the unit cost', () async {
      await shop.purchases.createPurchase(PurchaseInput(lines: [
        PurchaseLineInput(productId: phone, unitQty: 2, unitCost: rs(40000), imeis: const [
          ImeiInput(imei1: '350000000000011'),
          ImeiInput(imei1: '350000000000029'),
        ]),
      ], discount: const Money(1), paid: const Money(7999999)));
      final u = await units();
      expect(u.map((x) => x.cost.paisa).toList()..sort(), [3999999, 4000000]);
      await shop.sales.createSale(SaleInput(
          lines: [SaleLineInput(productId: phone, imeiUnitId: u.first.id, unitPrice: rs(45000))]));
      expect(await shop.bal(SysAccount.cogs), u.first.cost);
      await shop.expectHealthy();
    });

    test('an IMEI cannot be sold twice and cannot be in stock twice', () async {
      await shop.products.addOpeningStock(phone, imeis: [ImeiInput(imei1: '111', cost: rs(30000))]);
      await expectLater(shop.products.addOpeningStock(phone, imeis: [ImeiInput(imei1: '111', cost: rs(30000))]),
          throwsPosting(PostingError.imeiDuplicate));
      final unit = (await units()).single;
      await shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: phone, imeiUnitId: unit.id, unitPrice: rs(40000))]));
      await expectLater(
          shop.sales.createSale(
              SaleInput(lines: [SaleLineInput(productId: phone, imeiUnitId: unit.id, unitPrice: rs(40000))])),
          throwsPosting(PostingError.imeiNotAvailable));
      await expectLater(
          shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: phone, unitPrice: rs(40000))])),
          throwsPosting(PostingError.imeiRequired));
      await shop.expectHealthy();
    });

    test('returned IMEI goes back in stock and can be sold again', () async {
      await shop.products.addOpeningStock(phone, imeis: [ImeiInput(imei1: '222', cost: rs(30000))]);
      final unit = (await units()).single;
      final s = await shop.sales.createSale(
          SaleInput(lines: [SaleLineInput(productId: phone, imeiUnitId: unit.id, unitPrice: rs(40000))]));
      final si = (await shop.db.select(shop.db.saleItems).get()).single;
      await shop.sales.returnSale(saleId: s.saleId, lines: [SaleReturnLine(saleItemId: si.id, qty: 1)]);
      expect((await units()).single.status, ImeiStatus.inStock);
      await shop.sales.createSale(
          SaleInput(lines: [SaleLineInput(productId: phone, imeiUnitId: unit.id, unitPrice: rs(41000))]));
      await shop.expectHealthy();
    });

    test('IMEI write-off and purchase return of a unit', () async {
      final sup = await shop.supplier('Distributor');
      final p = await shop.purchases.createPurchase(PurchaseInput(partyId: sup, lines: [
        PurchaseLineInput(productId: phone, unitQty: 2, unitCost: rs(40000), imeis: const [
          ImeiInput(imei1: 'A1'),
          ImeiInput(imei1: 'A2'),
        ]),
      ], paid: Money.zero));
      final u = await units();
      final pi = (await shop.db.select(shop.db.purchaseItems).get()).single;
      await shop.purchases.returnPurchase(
          purchaseId: p.purchaseId, lines: [PurchaseReturnLine(purchaseItemId: pi.id, imeiUnitIds: [u[0].id])]);
      await shop.products.adjustStock(productId: phone, reason: AdjustmentReason.lost, imeiUnitId: u[1].id);
      expect(await shop.party(sup), -rs(40000));
      expect((await shop.stock(phone)).qtyOnHand, 0);
      expect(await shop.bal(SysAccount.stockLoss), rs(40000));
      await shop.expectHealthy();
    });
  });

  group('Repair jobs (8.1)', () {
    late TestShop shop;
    late String c;
    late String part;
    setUp(() async {
      shop = await TestShop.create();
      c = await shop.customer('Imran');
      part = await shop.products.createProduct(ProductInput(name: 'Screen', salePrice: rs(3000)),
          openingQty: 5, openingCost: rs(1800));
    });

    test('full lifecycle: advance, parts, return part, deliver, pay', () async {
      final job = await shop.repairs.createJob(
          partyId: c, deviceModel: 'Redmi 12', problem: 'Broken screen', estimate: rs(4000), advance: rs(1000));
      expect(await shop.bal(SysAccount.cash), rs(1000));
      expect(await shop.ledger.refBalance(job.jobId), -rs(1000));
      expect(await shop.bal(SysAccount.repairIncome), Money.zero); // job created: no entry

      for (final s in [RepairStatus.diagnosing, RepairStatus.waitingParts]) {
        await shop.repairs.changeStatus(job.jobId, s);
      }
      await shop.repairs.issuePart(job.jobId, productId: part, qty: 2, charge: rs(3000));
      expect(await shop.bal(SysAccount.cogs), rs(3600));
      await shop.repairs.returnPart(job.jobId, productId: part);
      expect(await shop.bal(SysAccount.cogs), rs(1800));
      expect((await shop.stock(part)).qtyOnHand, 4);
      await shop.repairs.changeStatus(job.jobId, RepairStatus.ready);

      await shop.repairs.deliver(job.jobId, finalAmount: rs(4000), paidNow: rs(2500));
      expect(await shop.bal(SysAccount.repairIncome), -rs(4000));
      expect(await shop.ledger.refBalance(job.jobId), rs(500));
      expect(await shop.party(c), rs(500));
      await shop.repairs.collect(job.jobId, rs(500));
      expect(await shop.ledger.refBalance(job.jobId), Money.zero);
      final logs = await (shop.db.select(shop.db.repairStatusLogs)..where((l) => l.jobId.equals(job.jobId))).get();
      expect(logs.map((l) => l.toStatus).last, RepairStatus.delivered);
      await expectLater(shop.repairs.issuePart(job.jobId, productId: part), throwsPosting(PostingError.invalidInput));
      await shop.expectHealthy();
    });

    test('returned unrepaired with fee; advance refunded; parts stay as cost', () async {
      final job = await shop.repairs.createJob(partyId: c, deviceModel: 'iPhone 11', problem: 'No power', advance: rs(1500));
      await shop.repairs.issuePart(job.jobId, productId: part);
      await shop.repairs.returnUnrepaired(job.jobId, fee: rs(500));
      expect(await shop.ledger.refBalance(job.jobId), -rs(1000));
      await shop.repairs.refundAdvance(job.jobId, rs(1000));
      expect(await shop.ledger.refBalance(job.jobId), Money.zero);
      expect(await shop.bal(SysAccount.repairIncome), -rs(500));
      expect(await shop.bal(SysAccount.cogs), rs(1800));
      expect(await shop.bal(SysAccount.cash), rs(500));
      await expectLater(shop.repairs.refundAdvance(job.jobId, rs(1)), throwsPosting(PostingError.overpayment));
      await shop.expectHealthy();
    });
  });

  group('Qist (8.1)', () {
    late TestShop shop;
    late String c;
    late String phone;
    late ImeiUnit unit;
    setUp(() async {
      shop = await TestShop.create();
      c = await shop.customer('Naveed');
      phone = await shop.product('Infinix Hot 40', price: rs(36000), imei: true);
      await shop.products.addOpeningStock(phone, imeis: [ImeiInput(imei1: '999', cost: rs(30000))]);
      unit = (await shop.db.select(shop.db.imeiUnits).get()).single;
    });

    Future<SaleResult> qistSale({Money markup = const Money(600000), Money down = const Money(1000000)}) =>
        shop.sales.createSale(SaleInput(
          partyId: c,
          lines: [SaleLineInput(productId: phone, imeiUnitId: unit.id, unitPrice: rs(36000))],
          mode: SalePaymentMode.qist,
          qist: QistInput(markup: markup, downPayment: down, installments: 4, guarantorName: 'Tariq'),
        ));

    test('qist sale: Dr AR T, Cr Sales P + DEFERRED_MARKUP M; down payment earns markup', () async {
      final r = await qistSale(); // P 36000, M 6000, T 42000, D 10000
      expect(r.total, rs(42000));
      expect(await shop.bal(SysAccount.sales), -rs(36000));
      expect(await shop.bal(SysAccount.cash), rs(10000));
      final dmEarned = rs(6000).ratio(10000, 42000);
      expect(await shop.bal(SysAccount.markupIncome), -dmEarned);
      expect(await shop.bal(SysAccount.deferredMarkup), -(rs(6000) - dmEarned));
      expect(await shop.party(c), rs(32000));
      final rows = await shop.db.select(shop.db.qistSchedule).get();
      expect(rows, hasLength(4));
      expect(Money.sum(rows.map((r) => r.amountDue)), rs(32000));
      expect(rows.first.dueDate, DateTime(2026, 11, 1));
      await shop.expectHealthy();
    });

    test('instalments apply oldest first, partial rows, plan completes and all markup is earned', () async {
      final r = await qistSale();
      await shop.qist.collect(r.planId!, rs(5000)); // row 1 partial (8000 due)
      var rows = await (shop.db.select(shop.db.qistSchedule)..orderBy([(x) => OrderingTerm.asc(x.seq)])).get();
      expect(rows[0].status, QistRowStatus.partial);
      expect(rows[0].amountPaid, rs(5000));
      await shop.qist.collect(r.planId!, rs(12000)); // finishes row 1, row 2, part of row 3
      rows = await (shop.db.select(shop.db.qistSchedule)..orderBy([(x) => OrderingTerm.asc(x.seq)])).get();
      expect(rows.map((x) => x.status).toList(),
          [QistRowStatus.paid, QistRowStatus.paid, QistRowStatus.partial, QistRowStatus.due]);
      await shop.qist.collect(r.planId!, rs(15000));
      final plan = await shop.db.select(shop.db.qistPlans).getSingle();
      expect(plan.status, QistPlanStatus.completed);
      expect(await shop.bal(SysAccount.markupIncome), -rs(6000));
      expect(await shop.bal(SysAccount.deferredMarkup), Money.zero);
      expect(await shop.party(c), Money.zero);
      await expectLater(shop.qist.collect(r.planId!, rs(1)), throwsPosting(PostingError.invalidInput));
      await shop.expectHealthy();
    });

    test('reversing an instalment payment re-opens the schedule and un-earns its markup', () async {
      final r = await qistSale();
      final pay = await shop.qist.collect(r.planId!, rs(8000));
      final earnedBefore = await shop.bal(SysAccount.markupIncome);
      await shop.payments.reverse(pay);
      final rows = await (shop.db.select(shop.db.qistSchedule)..orderBy([(x) => OrderingTerm.asc(x.seq)])).get();
      expect(rows.first.status, QistRowStatus.due);
      expect(await shop.bal(SysAccount.markupIncome), -rs(6000).ratio(10000, 42000));
      expect(earnedBefore, isNot(await shop.bal(SysAccount.markupIncome)));
      await shop.expectHealthy();
    });

    test('cancellation with device taken back, then write-off of the rest', () async {
      final r = await qistSale();
      await shop.qist.collect(r.planId!, rs(8000));
      final unearned = rs(6000) - (-(await shop.bal(SysAccount.markupIncome)));
      await shop.qist.cancelWithRecovery(r.planId!, recoveryValue: rs(20000));
      expect(await shop.bal(SysAccount.deferredMarkup), Money.zero);
      final owed = await shop.ledger.refBalance(r.planId!);
      expect(owed, rs(24000) - rs(20000) - unearned);
      final u = (await shop.db.select(shop.db.imeiUnits).get()).single;
      expect(u.status, ImeiStatus.inStock);
      expect(u.cost, rs(20000));
      await shop.qist.writeOff(r.planId!);
      expect(await shop.ledger.refBalance(r.planId!), Money.zero);
      expect(await shop.bal(SysAccount.badDebt), owed);
      await shop.expectHealthy();
    });

    test('plan with M = 0 skips markup lines; write-off of active plan clears deferred markup', () async {
      final r = await qistSale(markup: Money.zero, down: Money.zero);
      expect(await shop.bal(SysAccount.markupIncome), Money.zero);
      await shop.qist.writeOff(r.planId!);
      expect(await shop.bal(SysAccount.badDebt), rs(36000));
      await shop.expectHealthy();
    });

    test('schedule generation is exact and handles month ends', () {
      final rows = buildQistSchedule(
          financed: const Money(1000001), count: 3, frequency: QistFrequency.monthly, start: DateTime(2026, 1, 31));
      expect(rows.map((r) => r.amount.paisa).toList(), [333334, 333334, 333333]);
      expect(rows.map((r) => r.due).toList(), [DateTime(2026, 1, 31), DateTime(2026, 2, 28), DateTime(2026, 3, 31)]);
      final weekly = buildQistSchedule(financed: rs(100), count: 2, frequency: QistFrequency.weekly, start: DateTime(2026, 1, 1));
      expect(weekly.last.due, DateTime(2026, 1, 8));
    });

    test('markup earned is cumulative and sums to M exactly', () {
      var before = Money.zero;
      var earned = Money.zero;
      for (final a in [const Money(333), const Money(333), const Money(334)]) {
        earned += markupEarned(markup: const Money(100), total: const Money(1000), paidBefore: before, paidNow: a);
        before += a;
      }
      expect(earned, const Money(100));
    });
  });

  group('Used phone purchase', () {
    test('Dr Inventory, Cr Cash; unit in stock at price; reversal', () async {
      final shop = await TestShop.create();
      final used = await shop.product('Used iPhone', price: rs(60000), imei: true);
      final seller = await shop.customer('Walk-in seller');
      final r = await shop.usedPhones.purchase(
          sellerPartyId: seller,
          productId: used,
          model: 'iPhone 12 64GB',
          imei1: '356789',
          grade: ConditionGrade.b,
          price: rs(52000));
      expect(await shop.bal(SysAccount.inventory), rs(52000));
      expect(await shop.bal(SysAccount.cash), -rs(52000));
      expect((await shop.stock(used)).qtyOnHand, 1);
      await shop.usedPhones.reverse(r.id);
      expect(await shop.bal(SysAccount.inventory), Money.zero);
      await shop.expectHealthy();
    });
  });
}
