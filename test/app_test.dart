import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/app/app.dart';
import 'package:smart_dukan/core/settings/app_preferences.dart';

Future<ProviderContainer> pumpApp(WidgetTester tester) async {
  // Typical small Android phone.
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SmartDukanApp()));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('launches on Home in Roman Urdu with 5 tabs and the Nayi Sale button', (tester) async {
    await pumpApp(tester);

    expect(find.text('Aaj ka Hisaab'), findsOneWidget);
    expect(find.text('Offline • Mehfooz'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.byKey(const Key('fab_new_sale')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tab opens without errors', (tester) async {
    await pumpApp(tester);
    for (final label in ['Sale', 'Khata', 'Stock', 'Aur', 'Home']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'tab $label');
    }
  });

  testWidgets('centre button opens the Sale tab and hides itself', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('fab_new_sale')));
    await tester.pumpAndSettle();
    expect(find.text('Sale shuru karein'), findsOneWidget);
    expect(find.byKey(const Key('fab_new_sale')), findsNothing);
  });

  for (final lang in AppLanguage.values) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('Home renders without overflow: ${lang.name} / ${mode.name}', (tester) async {
        final container = await pumpApp(tester);
        container.read(appPreferencesProvider.notifier)
          ..setLanguage(lang)
          ..setThemeMode(mode);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Urdu mode mirrors the layout (RTL)', (tester) async {
    final container = await pumpApp(tester);
    container.read(appPreferencesProvider.notifier).setLanguage(AppLanguage.urdu);
    await tester.pumpAndSettle();

    final ctx = tester.element(find.text('آج کا حساب'));
    expect(Directionality.of(ctx), TextDirection.rtl);
  });
}
