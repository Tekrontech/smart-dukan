import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/accounting/posting.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/core/settings/app_preferences.dart';
import 'package:smart_dukan/features/parties/application/party_service.dart';
import 'package:smart_dukan/features/products/application/product_service.dart';
import 'package:smart_dukan/features/sales/application/sale_service.dart';

import '../helpers/app_harness.dart';

/// Golden screenshots of Home and Sale in English and Urdu, light and dark
/// (spec Section 10). Regenerate after intended UI changes with:
///   flutter test test/goldens --update-goldens
/// Font rendering differs slightly between OSes; generate and compare on
/// the same machine type (CI or your laptop).
final _now = DateTime(2026, 10, 15, 18, 30);

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await family('Inter', ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf']);
  await family('NotoNastaliqUrdu', ['NotoNastaliqUrdu-Regular.ttf', 'NotoNastaliqUrdu-Bold.ttf']);
  await family('NotoNaskhArabic', ['NotoNaskhArabic-Regular.ttf', 'NotoNaskhArabic-Bold.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

Future<void> _seed(AppDatabase db, BusinessCtx ctx) async {
  final c = BusinessCtx(businessId: ctx.businessId, userId: ctx.userId, clock: () => _now);
  final products = ProductService(db, c);
  final charger = await products.createProduct(const ProductInput(name: 'Fast Charger 25W', salePrice: Money.rupees(1500)),
      openingQty: 20, openingCost: const Money.rupees(900));
  await products.createProduct(const ProductInput(name: 'Type-C Cable', salePrice: Money.rupees(450), minStock: 10),
      openingQty: 6, openingCost: const Money.rupees(200));
  await products.createProduct(const ProductInput(name: 'Glass Protector 9D', salePrice: Money.rupees(300)),
      openingQty: 50, openingCost: const Money.rupees(80));
  final ali = await PartyService(db, c).createParty(const PartyInput(type: PartyType.customer, name: 'Ali Raza'));
  await SaleService(db, c).createSale(SaleInput(lines: [SaleLineInput(productId: charger, unitQty: 2, unitPrice: const Money.rupees(1500))]));
  await SaleService(db, c).createSale(SaleInput(
      partyId: ali,
      lines: [SaleLineInput(productId: charger, unitPrice: const Money.rupees(1500))],
      mode: SalePaymentMode.udhaar));
}

void main() {
  setUpAll(_loadFonts);

  for (final lang in [AppLanguage.english, AppLanguage.urdu]) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      final tag = '${lang == AppLanguage.urdu ? 'ur' : 'en'}_${theme.name}';

      testWidgets('golden Home $tag', (tester) async {
        await pumpApp(tester, language: lang, theme: theme, seed: _seed, now: _now, size: const Size(1080, 2340));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('home_$tag.png'));
      });

      testWidgets('golden Sale $tag', (tester) async {
        await pumpApp(tester, language: lang, theme: theme, seed: _seed, now: _now, size: const Size(1080, 2340));
        await tester.tap(find.byKey(const Key('fab_new_sale')));
        await settle(tester);
        await tester.tap(find.text('Fast Charger 25W'));
        await settle(tester);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('sale_$tag.png'));
      });
    }
  }
}
