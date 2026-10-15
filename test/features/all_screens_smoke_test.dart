import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/app/app.dart';
import 'package:smart_dukan/app/router.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/core/settings/app_preferences.dart';
import 'package:smart_dukan/features/onboarding/application/demo_data_service.dart';
import 'package:smart_dukan/features/reports/application/reports_service.dart';
import 'package:smart_dukan/features/sales/application/sale_service.dart';

import '../helpers/app_harness.dart';

/// Opens every screen on the demo shop and fails on any exception or
/// layout overflow — in all three languages.
void main() {
  for (final lang in AppLanguage.values) {
    testWidgets('every screen opens cleanly on demo data: ${lang.name}', (tester) async {
      late String saleId, productId, imeiProductId, partyId, purchaseId, planId;
      final h = await pumpApp(tester, language: lang, seed: (db, ctx) async {
        await DemoDataService(db, businessId: ctx.businessId, userId: ctx.userId).load();
        final c = (await (db.select(db.parties)..where((p) => p.type.equalsValue(PartyType.customer))..limit(1)).getSingle()).id;
        final phone = await (db.select(db.products)..where((p) => p.tracksImei.equals(true))..limit(1)).getSingle();
        final unit = await (db.select(db.imeiUnits)
              ..where((u) => u.productId.equals(phone.id) & u.status.equalsValue(ImeiStatus.inStock))
              ..limit(1))
            .getSingle();
        final r = await SaleService(db, ctx).createSale(SaleInput(
          partyId: c,
          lines: [SaleLineInput(productId: phone.id, imeiUnitId: unit.id, unitPrice: phone.salePrice)],
          mode: SalePaymentMode.qist,
          qist: const QistInput(markup: Money.rupees(5000), downPayment: Money.rupees(10000), installments: 6),
        ));
        planId = r.planId!;
      });
      await tester.runAsync(() async {
        final db = h.db;
        saleId = (await (db.select(db.sales)..where((s) => s.paymentMode.equalsValue(SalePaymentMode.cash))..limit(1)).getSingle()).id;
        productId = (await (db.select(db.products)..where((p) => p.tracksImei.equals(false))..limit(1)).getSingle()).id;
        imeiProductId = (await (db.select(db.products)..where((p) => p.tracksImei.equals(true))..limit(1)).getSingle()).id;
        partyId = (await (db.select(db.parties)..limit(1)).getSingle()).id;
        purchaseId = (await (db.select(db.purchases)..limit(1)).getSingle()).id;
      });

      final routes = <String>[
        Routes.home,
        Routes.sale,
        Routes.khata,
        Routes.stock,
        Routes.more,
        Routes.salesList,
        Routes.saleDetail(saleId),
        Routes.saleReturn(saleId),
        Routes.productNew,
        Routes.product(productId),
        Routes.product(imeiProductId),
        Routes.productEdit(productId),
        Routes.productImport,
        Routes.purchaseNew,
        Routes.purchasesList,
        Routes.purchaseDetail(purchaseId),
        Routes.partyNew(PartyType.customer),
        Routes.party(partyId),
        Routes.partyEdit(partyId),
        Routes.paymentNew(incoming: true, partyId: partyId),
        Routes.paymentNew(incoming: false),
        Routes.expenseNew,
        Routes.expensesList,
        Routes.galla,
        Routes.reports,
        for (final k in ReportKind.values) Routes.report(k.name),
        Routes.imeiSearch,
        Routes.usedPhoneList,
        Routes.usedPhoneNew,
        Routes.repairs,
        Routes.repairNew,
        Routes.qistList,
        Routes.qist(planId),
        Routes.shopProfile,
        Routes.security,
        Routes.staff,
        Routes.backup,
        Routes.license,
        Routes.healthCheck,
        '${Routes.info}/privacy',
        '${Routes.info}/terms',
        '${Routes.info}/help',
      ];
      final router = h.container.read(routerProvider);
      final failures = <String>[];
      final oldHandler = FlutterError.onError;
      String? current;
      FlutterError.onError = (d) {
        failures.add('$current: ${d.exceptionAsString().split('\n').first} @ ${d.informationCollector?.call().take(2).join(' | ')}');
      };
      try {
        for (final r in routes) {
          current = r;
          router.go(r);
          await settle(tester);
        }
      } finally {
        FlutterError.onError = oldHandler;
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
      // The Health Check screen on demo data reports zero errors (spec 10).
      router.go(Routes.healthCheck);
      await settle(tester);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });
  }
}
