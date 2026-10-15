import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/accounting/posting.dart';
import '../../../core/db/app_database.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/utils/ids.dart';
import '../../expenses/application/expense_service.dart';
import '../../parties/application/party_service.dart';
import '../../payments/application/payment_service.dart';
import '../../products/application/product_service.dart';
import '../../purchases/application/purchase_service.dart';
import '../../sales/application/sale_service.dart';

/// Sample mobile shop (spec Section 11, Prompt 3): 30 products including
/// IMEI phones, 10 customers, 3 suppliers and two weeks of sales. Every
/// entry goes through the real posting services, so the demo books
/// reconcile like real ones. Wiped with one tap ([wipe]).
class DemoDataService {
  DemoDataService(this.db, {required this.businessId, this.userId, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  final AppDatabase db;
  final String businessId;
  final String? userId;
  final DateTime Function() clock;

  static const _phones = [
    ('Samsung Galaxy A15 128GB', 'Samsung', 45999, 41500),
    ('Samsung Galaxy A25 256GB', 'Samsung', 69999, 64000),
    ('Redmi 13C 128GB', 'Xiaomi', 34999, 31500),
    ('Redmi Note 13 256GB', 'Xiaomi', 59999, 55000),
    ('Infinix Hot 40 256GB', 'Infinix', 39999, 36000),
    ('Tecno Spark 20 128GB', 'Tecno', 32999, 29500),
    ('Vivo Y03 64GB', 'Vivo', 25999, 23000),
    ('Oppo A18 128GB', 'Oppo', 31999, 28800),
  ];

  static const _accessories = [
    ('Fast Charger 25W', 'Chargers', 1500, 900, 25),
    ('Car Charger Dual USB', 'Chargers', 800, 450, 15),
    ('Type-C Cable 1m', 'Cables', 450, 200, 60),
    ('Lightning Cable 1m', 'Cables', 600, 280, 30),
    ('Micro USB Cable', 'Cables', 300, 120, 40),
    ('Silicone Cover A15', 'Covers', 500, 180, 30),
    ('Silicone Cover Redmi 13C', 'Covers', 500, 180, 30),
    ('Leather Flip Cover', 'Covers', 900, 400, 20),
    ('Glass Protector 9D', 'Protectors', 300, 80, 100),
    ('Privacy Glass Protector', 'Protectors', 700, 250, 30),
    ('Wired Handsfree', 'Audio', 400, 180, 40),
    ('TWS Earbuds', 'Audio', 2800, 1900, 12),
    ('Bluetooth Neckband', 'Audio', 1800, 1100, 10),
    ('Power Bank 10000mAh', 'Power', 3500, 2600, 10),
    ('Power Bank 20000mAh', 'Power', 5500, 4200, 6),
    ('Memory Card 64GB', 'Storage', 1600, 1150, 15),
    ('USB Flash 32GB', 'Storage', 1000, 650, 15),
    ('Phone Stand', 'Accessories', 400, 150, 20),
    ('Selfie Stick', 'Accessories', 900, 500, 8),
    ('Ring Light 10 inch', 'Accessories', 2500, 1700, 5),
    ('SIM Ejector Pin (pack)', 'Accessories', 100, 20, 50),
    ('Screen Cleaning Kit', 'Accessories', 350, 120, 20),
  ];

  static const _customers = [
    'Ali Raza', 'Bilal Ahmed', 'Hamza Khan', 'Usman Tariq', 'Saad Iqbal',
    'Ayesha Noor', 'Fatima Malik', 'Zeeshan Ali', 'Imran Shah', 'Naveed Akhtar',
  ];

  static const _suppliers = [('Hall Road Traders', 25000), ('Karachi Mobile Mart', 0), ('Star Accessories', 8000)];

  Future<void> load() async {
    final rnd = Random(42);
    final start = clock();
    final today = DateTime(start.year, start.month, start.day);
    final opening = today.subtract(const Duration(days: 14));
    var now = DateTime(opening.year, opening.month, opening.day, 9);

    BusinessCtx ctxAt(DateTime t) => BusinessCtx(businessId: businessId, userId: userId, clock: () => t);

    // Go-live = two weeks ago, so opening balances sit before the sales.
    await (db.update(db.businesses)..where((b) => b.id.equals(businessId)))
        .write(BusinessesCompanion(goLiveDate: Value(opening)));

    final ctx0 = ctxAt(now);
    final products = ProductService(db, ctx0);
    final categories = <String, String>{};
    final brands = <String, String>{};
    Future<String> cat(String n) async => categories[n] ??= await products.createCategory(n);
    Future<String> brand(String n) async => brands[n] ??= await products.createBrand(n);

    final phoneIds = <String>[];
    var imeiSeed = 356000000000000;
    for (final ph in _phones) {
      final units = 2 + rnd.nextInt(2);
      final id = await products.createProduct(
        ProductInput(
          name: ph.$1,
          categoryId: await cat('Mobiles'),
          brandId: await brand(ph.$2),
          salePrice: Money.rupees(ph.$3),
          minSalePrice: Money.rupees(ph.$4),
          tracksImei: true,
          warrantyDays: 365,
        ),
        openingImeis: [
          for (var i = 0; i < units; i++) ImeiInput(imei1: '${imeiSeed += 7919}', cost: Money.rupees(ph.$4)),
        ],
      );
      phoneIds.add(id);
    }
    final accIds = <(String, Money)>[];
    for (final a in _accessories) {
      final id = await products.createProduct(
        ProductInput(
          name: a.$1,
          categoryId: await cat(a.$2),
          salePrice: Money.rupees(a.$3),
          minStock: (a.$5 / 5).ceil(),
        ),
        openingQty: a.$5,
        openingCost: Money.rupees(a.$4),
      );
      accIds.add((id, Money.rupees(a.$3)));
    }

    final parties = PartyService(db, ctx0);
    final customerIds = <String>[];
    for (var i = 0; i < _customers.length; i++) {
      customerIds.add(await parties.createParty(
        PartyInput(type: PartyType.customer, name: _customers[i], phone: '0300${(1234567 + i * 1111).toString()}'),
        openingBalance: i % 4 == 0 ? Money.rupees(1500 + i * 250) : Money.zero,
      ));
    }
    final supplierIds = <String>[];
    for (final s in _suppliers) {
      supplierIds.add(await parties.createParty(
        PartyInput(type: PartyType.supplier, name: s.$1, phone: '0321${(7654321 - s.$2 ~/ 10)}'),
        openingBalance: -Money.rupees(s.$2),
      ));
    }
    await PaymentService(db, ctx0).openingBalance(amount: const Money.rupees(20000));

    final chai = (await (db.select(db.expenseCategories)..where((c) => c.systemKey.equals('chai_pani'))).getSingle()).id;

    for (var day = 0; day <= 14; day++) {
      final date = opening.add(Duration(days: day));
      now = DateTime(date.year, date.month, date.day, 10, rnd.nextInt(50));
      if (now.isAfter(start)) now = start.subtract(const Duration(minutes: 30));

      final salesToday = 3 + rnd.nextInt(4);
      for (var s = 0; s < salesToday; s++) {
        now = now.add(Duration(minutes: 20 + rnd.nextInt(60)));
        final ctx = ctxAt(now);
        final lines = <SaleLineInput>[];
        if (rnd.nextInt(5) == 0) {
          final pid = phoneIds[rnd.nextInt(phoneIds.length)];
          final unit = await (db.select(db.imeiUnits)
                ..where((u) => u.productId.equals(pid) & u.status.equalsValue(ImeiStatus.inStock))
                ..limit(1))
              .getSingleOrNull();
          if (unit != null) {
            final product = await (db.select(db.products)..where((p) => p.id.equals(pid))).getSingle();
            lines.add(SaleLineInput(productId: pid, imeiUnitId: unit.id, unitPrice: product.salePrice));
          }
        }
        final n = 1 + rnd.nextInt(3);
        for (var k = 0; k < n; k++) {
          final a = accIds[rnd.nextInt(accIds.length)];
          final bal = await (db.select(db.stockBalances)..where((b) => b.stockKey.equals(stockKeyOf(a.$1, null))))
              .getSingleOrNull();
          final qty = 1 + rnd.nextInt(2);
          if ((bal?.qtyOnHand ?? 0) >= qty + 2 && !lines.any((l) => l.productId == a.$1)) {
            lines.add(SaleLineInput(productId: a.$1, unitQty: qty, unitPrice: a.$2));
          }
        }
        if (lines.isEmpty) continue;
        final roll = rnd.nextInt(10);
        final customer = customerIds[rnd.nextInt(customerIds.length)];
        final mode = roll < 6 ? SalePaymentMode.cash : (roll < 8 ? SalePaymentMode.udhaar : SalePaymentMode.mixed);
        final total = SaleService.totals(lines).total;
        await SaleService(db, ctx).createSale(SaleInput(
          partyId: mode == SalePaymentMode.cash && rnd.nextBool() ? null : customer,
          lines: lines,
          mode: mode,
          paidNow: mode == SalePaymentMode.mixed ? Money.rupees((total.paisa ~/ 200) ~/ 100 * 100) : null,
        ));
      }

      now = now.add(const Duration(minutes: 30));
      await ExpenseService(db, ctxAt(now)).create(categoryId: chai, amount: Money.rupees(150 + rnd.nextInt(4) * 50));

      if (day % 3 == 1) {
        now = now.add(const Duration(minutes: 10));
        final c = customerIds[rnd.nextInt(customerIds.length)];
        final owed = await _balance(c);
        if (owed > const Money.rupees(500)) {
          await PaymentService(db, ctxAt(now)).receive(partyId: c, amount: const Money.rupees(500));
        }
      }
      if (day == 6) {
        now = now.add(const Duration(minutes: 10));
        await PurchaseService(db, ctxAt(now)).createPurchase(PurchaseInput(
          partyId: supplierIds[2],
          lines: [
            PurchaseLineInput(productId: accIds[0].$1, unitQty: 10, unitCost: const Money.rupees(920)),
            PurchaseLineInput(productId: accIds[2].$1, unitQty: 30, unitCost: const Money.rupees(210)),
          ],
          paid: const Money.rupees(5000),
        ));
      }
      if (day == 10) {
        now = now.add(const Duration(minutes: 10));
        await PaymentService(db, ctxAt(now)).pay(partyId: supplierIds[0], amount: const Money.rupees(10000));
      }
    }
    await SettingsRepository(db).set(SettingKeys.demoData, 'true', businessId: businessId);
  }

  Future<Money> _balance(String partyId) async {
    final r = await db.customSelect(
      'SELECT COALESCE(SUM(jl.debit - jl.credit),0) b FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key IN ('AR','AP') AND jl.party_id = ?",
      variables: [Variable.withString(partyId)],
    ).getSingle();
    return Money(r.read<int>('b'));
  }

  /// Deletes every product, party and entry. Keeps the shop, users,
  /// settings, chart of accounts, expense categories, units and licences.
  Future<void> wipe() async {
    await db.transaction(() async {
      for (final t in <TableInfo<Table, dynamic>>[
        db.categories, db.brands, db.products, db.productVariants, db.barcodes, db.stockMovements,
        db.stockBalances, db.imeiUnits, db.parties, db.sales, db.saleItems, db.saleReturns, db.saleReturnItems,
        db.purchases, db.purchaseItems, db.purchaseReturns, db.purchaseReturnItems, db.payments,
        db.paymentAllocations, db.expenses, db.stockAdjustments, db.journalEntries, db.journalLines,
        db.cashClosings, db.usedPhonePurchases, db.repairJobs, db.repairParts, db.repairStatusLogs,
        db.qistPlans, db.qistSchedule, db.docCounters,
      ]) {
        await db.delete(t).go();
      }
      final now = clock();
      await (db.update(db.businesses)..where((b) => b.id.equals(businessId)))
          .write(BusinessesCompanion(goLiveDate: Value(DateTime(now.year, now.month, now.day))));
      await SettingsRepository(db).set(SettingKeys.demoData, 'false', businessId: businessId);
      await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
            id: newId(),
            businessId: businessId,
            createdAt: now,
            updatedAt: now,
            createdBy: Value(userId),
            entity: 'business',
            entityId: businessId,
            action: 'wipe_demo',
            userId: Value(userId),
          ));
    });
  }
}
