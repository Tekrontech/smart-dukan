import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/features/pro_mobile/used_phones/application/used_phone_service.dart';
import 'package:smart_dukan/features/sales/application/sale_service.dart';

import '../helpers/test_shop.dart';

void main() {
  test('CNIC data is purged 12 months after the device is sold; the purchase record stays', () async {
    final shop = await TestShop.create();
    final used = await shop.product('Used iPhone', imei: true);
    final seller = await shop.customer('Seller');
    final r = await shop.usedPhones.purchase(
      sellerPartyId: seller,
      productId: used,
      model: 'iPhone 11',
      imei1: '351111',
      grade: ConditionGrade.a,
      price: rs(40000),
      sellerCnic: '35202-1234567-1',
      cnicFrontPath: 'front.enc',
      cnicBackPath: 'back.enc',
    );
    await shop.sales.createSale(SaleInput(lines: [SaleLineInput(productId: used, imeiUnitId: r.imeiUnitId, unitPrice: rs(45000))]));
    final shredded = <String>[];
    Future<void> shred(String n) async => shredded.add(n);

    TestShop.clock = TestShop.clock.add(const Duration(days: 200));
    expect(await UsedPhoneService(shop.db, shop.ctx).purgeExpiredIdentity(months: 12, shred: shred), 0);

    TestShop.clock = TestShop.clock.add(const Duration(days: 200));
    expect(await UsedPhoneService(shop.db, shop.ctx).purgeExpiredIdentity(months: 12, shred: shred), 1);
    expect(shredded, ['front.enc', 'back.enc']);
    final doc = await (shop.db.select(shop.db.usedPhonePurchases)..where((u) => u.id.equals(r.id))).getSingle();
    expect(doc.sellerCnic, isNull);
    expect(doc.cnicFrontPath, isNull);
    expect(doc.identityPurgedAt, isNotNull);
    expect(doc.price, rs(40000));
    final logs = await (shop.db.select(shop.db.auditLogs)..where((a) => a.action.equals('delete_identity'))).get();
    expect(logs, hasLength(1));
    expect(logs.single.afterJson, isNot(contains('35202')));
  });
}
