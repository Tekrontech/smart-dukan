import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/settings/app_preferences.dart';

import 'helpers/app_harness.dart';

void main() {
  testWidgets('launches on Home in Roman Urdu with 5 tabs and the Nayi Sale button', (tester) async {
    await pumpApp(tester);
    expect(find.text('Madina Mobiles'), findsOneWidget);
    expect(find.text('Offline • Mehfooz'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.byKey(const Key('fab_new_sale')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tab opens without errors', (tester) async {
    await pumpApp(tester);
    for (final label in ['Sale', 'Khata', 'Stock', 'Aur', 'Home']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'tab $label');
    }
  });

  testWidgets('centre button opens the Sale tab and hides itself', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('fab_new_sale')));
    await settle(tester);
    expect(find.text('Sale shuru karein'), findsOneWidget);
    expect(find.byKey(const Key('fab_new_sale')), findsNothing);
  });

  for (final lang in AppLanguage.values) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('Home renders without overflow: ${lang.name} / ${mode.name}', (tester) async {
        await pumpApp(tester, language: lang, theme: mode);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Urdu mode mirrors the layout (RTL), numbers stay LTR', (tester) async {
    await pumpApp(tester, language: AppLanguage.urdu);
    final ctx = tester.element(find.text('آف لائن • محفوظ'));
    expect(Directionality.of(ctx), TextDirection.rtl);
    final money = tester.element(find.text('Rs 0').first);
    expect(Directionality.of(money), TextDirection.ltr);
  });

  testWidgets('first launch goes to onboarding; locked app goes to the lock screen', (tester) async {
    await pumpApp(tester, onboarded: false);
    expect(find.text('Apni zubaan chunein'), findsOneWidget);
  });

  testWidgets('locked app shows the PIN pad and unlocks with the right PIN', (tester) async {
    await pumpApp(tester, locked: true);
    expect(find.text('PIN likhein'), findsOneWidget);
    for (final d in ['9', '9', '9', '9']) {
      await tester.tap(find.byKey(Key('pin_$d')));
    }
    await settle(tester);
    expect(find.text('Ghalat PIN'), findsOneWidget);
    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.byKey(Key('pin_$d')));
    }
    await settle(tester);
    expect(find.text('Offline • Mehfooz'), findsOneWidget);
  });
}
