import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/accounting/health_check.dart';
import 'package:smart_dukan/core/accounting/ledger_queries.dart';
import 'package:smart_dukan/core/accounting/posting.dart';
import 'package:smart_dukan/core/accounting/system_accounts.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/features/cash_closing/application/cash_closing_service.dart';
import 'package:smart_dukan/features/expenses/application/expense_service.dart';
import 'package:smart_dukan/features/onboarding/application/business_setup_service.dart';
import 'package:smart_dukan/features/parties/application/party_service.dart';
import 'package:smart_dukan/features/payments/application/payment_service.dart';
import 'package:smart_dukan/features/pro_mobile/qist/application/qist_service.dart';
import 'package:smart_dukan/features/pro_mobile/repairs/application/repair_service.dart';
import 'package:smart_dukan/features/pro_mobile/used_phones/application/used_phone_service.dart';
import 'package:smart_dukan/features/products/application/product_service.dart';
import 'package:smart_dukan/features/purchases/application/purchase_service.dart';
import 'package:smart_dukan/features/sales/application/sale_service.dart';

/// Rupees shorthand for tests.
Money rs(int rupees) => Money.rupees(rupees);

/// An in-memory shop with every service wired up and a controllable clock.
class TestShop {
  TestShop._(this.db, this.ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  static DateTime clock = DateTime(2026, 10, 1, 10);

  static Future<TestShop> create() async {
    clock = DateTime(2026, 10, 1, 10);
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory());
    final business = await BusinessSetupService(db, clock: () => clock)
        .createBusiness(name: 'Test Mobiles', ownerName: 'Ali', goLiveDate: DateTime(2026, 10, 1));
    final shop = TestShop._(db, BusinessCtx(businessId: business.id, userId: 'owner', clock: () => clock));
    addTearDown(db.close);
    return shop;
  }

  void advance(Duration d) => clock = clock.add(d);

  ProductService get products => ProductService(db, ctx);
  PartyService get parties => PartyService(db, ctx);
  SaleService get sales => SaleService(db, ctx);
  PurchaseService get purchases => PurchaseService(db, ctx);
  PaymentService get payments => PaymentService(db, ctx);
  ExpenseService get expenses => ExpenseService(db, ctx);
  CashClosingService get closing => CashClosingService(db, ctx);
  RepairService get repairs => RepairService(db, ctx);
  QistService get qist => QistService(db, ctx);
  UsedPhoneService get usedPhones => UsedPhoneService(db, ctx);
  LedgerQueries get ledger => LedgerQueries(db);

  Future<Money> bal(SysAccount a) => ledger.sysBalance(a);
  Future<Money> party(String id) => ledger.partyBalance(id);

  Future<StockBalance> stock(String productId, [String? variantId]) async =>
      (await (db.select(db.stockBalances)..where((b) => b.stockKey.equals(stockKeyOf(productId, variantId))))
          .getSingleOrNull()) ??
      StockBalance(
        id: '',
        businessId: '',
        createdAt: clock,
        updatedAt: clock,
        productId: productId,
        stockKey: '',
        qtyOnHand: 0,
        value: Money.zero,
      );

  Future<String> product(String name, {Money? price, bool imei = false, Money minPrice = Money.zero, String? unitId}) =>
      products.createProduct(ProductInput(
          name: name, salePrice: price ?? rs(100), tracksImei: imei, minSalePrice: minPrice, unitId: unitId));

  Future<String> customer(String name, {Money opening = Money.zero, Money limit = Money.zero}) => parties
      .createParty(PartyInput(type: PartyType.customer, name: name, creditLimit: limit), openingBalance: opening);

  Future<String> supplier(String name, {Money opening = Money.zero}) =>
      parties.createParty(PartyInput(type: PartyType.supplier, name: name), openingBalance: opening);

  Future<String> expenseCategory(String key) async =>
      (await (db.select(db.expenseCategories)..where((c) => c.systemKey.equals(key))).getSingle()).id;

  /// Every Section 8 invariant must hold after every test.
  Future<void> expectHealthy() async {
    final issues = await HealthCheck(db).run();
    expect(issues, isEmpty, reason: issues.join('\n'));
  }
}
