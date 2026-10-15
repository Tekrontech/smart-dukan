import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/accounting/health_check.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/features/onboarding/application/business_setup_service.dart';
import 'package:smart_dukan/features/onboarding/application/demo_data_service.dart';

void main() {
  test('demo shop loads 30 products, 10 customers, 3 suppliers, 2 weeks of sales and reconciles; wipe clears it',
      () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final b = await BusinessSetupService(db).createBusiness(name: 'Demo');
    final demo = DemoDataService(db, businessId: b.id, clock: () => DateTime(2026, 10, 15, 18));
    await demo.load();

    expect(await db.select(db.products).get(), hasLength(30));
    expect((await db.select(db.parties).get()).where((p) => p.type == PartyType.customer), hasLength(10));
    expect((await db.select(db.parties).get()).where((p) => p.type == PartyType.supplier), hasLength(3));
    final sales = await db.select(db.sales).get();
    expect(sales.length, greaterThan(30));
    final days = sales.map((s) => DateTime(s.date.year, s.date.month, s.date.day)).toSet();
    expect(days.length, greaterThanOrEqualTo(14));
    expect(await HealthCheck(db).run(), isEmpty);

    await demo.wipe();
    expect(await db.select(db.products).get(), isEmpty);
    expect(await db.select(db.journalLines).get(), isEmpty);
    expect(await db.select(db.accounts).get(), isNotEmpty);
    expect(await HealthCheck(db).run(), isEmpty);
  });
}
