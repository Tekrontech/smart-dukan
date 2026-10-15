import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/accounting/health_check.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/core/settings/app_preferences.dart';
import 'package:smart_dukan/features/products/application/product_service.dart';

import '../helpers/app_harness.dart';

Future<void> _seedCharger(AppDatabase db, dynamic ctx) async {
  await ProductService(db, ctx).createProduct(
    const ProductInput(name: 'Charger 20W', salePrice: Money.rupees(1500)),
    openingQty: 10,
    openingCost: const Money.rupees(900),
  );
}

Future<List<Sale>> _sales(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(() => db.select(db.sales).get()))!;

void main() {
  testWidgets('known item, cash sale, in 3 taps: one invoice, books balance', (tester) async {
    final h = await pumpApp(tester, seed: _seedCharger);
    // Tap 1: open Sale.  Tap 2: the product.  Tap 3: Save.
    await tester.tap(find.byKey(const Key('fab_new_sale')));
    await settle(tester);
    await tester.tap(find.text('Charger 20W'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('save_sale')));
    await settle(tester);

    expect(find.text('Rs 1,500'), findsWidgets);
    expect(find.byKey(const Key('success_new_sale')), findsOneWidget);
    final sales = await _sales(tester, h.db);
    expect(sales, hasLength(1));
    expect(sales.single.total, const Money.rupees(1500));
    expect(sales.single.paymentMode, SalePaymentMode.cash);
    expect(await tester.runAsync(() => HealthCheck(h.db).run()), isEmpty);
  });

  testWidgets('double-tap on Save creates exactly one invoice', (tester) async {
    final h = await pumpApp(tester, seed: _seedCharger);
    await tester.tap(find.byKey(const Key('fab_new_sale')));
    await settle(tester);
    await tester.tap(find.text('Charger 20W'));
    await settle(tester);
    final save = find.byKey(const Key('save_sale'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await settle(tester);
    expect(await _sales(tester, h.db), hasLength(1));
  });

  testWidgets('Udhaar requires a named customer', (tester) async {
    final h = await pumpApp(tester, seed: _seedCharger);
    await tester.tap(find.byKey(const Key('fab_new_sale')));
    await settle(tester);
    await tester.tap(find.text('Charger 20W'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('cart_open')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('mode_udhaar')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('save_sale')).last);
    await settle(tester);
    // The customer picker opens instead of saving.
    expect(find.text('Naya gahak add karein'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(await _sales(tester, h.db), isEmpty);
  });

  for (final lang in [AppLanguage.urdu, AppLanguage.english]) {
    testWidgets('Sale screen and cart render without overflow: ${lang.name}', (tester) async {
      await pumpApp(tester, seed: _seedCharger, language: lang);
      await tester.tap(find.byKey(const Key('fab_new_sale')));
      await settle(tester);
      await tester.tap(find.text('Charger 20W'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('cart_open')));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('onboarding: language, shop, no demo, PIN twice → Home', (tester) async {
    final h = await pumpApp(tester, onboarded: false);
    await tester.tap(find.byKey(const Key('lang_english')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('onb_next')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('shop_name')), 'Star Mobiles');
    await tester.enterText(find.byKey(const Key('owner_name')), 'Hamid');
    await tester.tap(find.byKey(const Key('onb_next')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('demo_no')));
    await tester.tap(find.byKey(const Key('onb_next')));
    await settle(tester);
    for (var round = 0; round < 2; round++) {
      for (final d in ['2', '5', '8', '0']) {
        await tester.tap(find.byKey(Key('pin_$d')));
      }
      await settle(tester);
    }
    await settle(tester);
    expect(find.text('Star Mobiles'), findsOneWidget);
    expect(find.text('Offline • Safe'), findsOneWidget);
    final users = await tester.runAsync(() => h.db.select(h.db.users).get());
    expect(users!.single.role, UserRole.owner);
  });
}
