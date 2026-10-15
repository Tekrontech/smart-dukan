import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/app/app.dart';
import 'package:smart_dukan/app/providers.dart';
import 'package:smart_dukan/core/accounting/posting.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/core/security/biometric_service.dart';
import 'package:smart_dukan/core/security/key_store.dart';
import 'package:smart_dukan/core/security/pin_gate.dart';
import 'package:smart_dukan/core/security/pin_service.dart';
import 'package:smart_dukan/core/settings/app_preferences.dart';
import 'package:smart_dukan/core/settings/settings_repository.dart';
import 'package:smart_dukan/features/onboarding/application/business_setup_service.dart';
import 'package:smart_dukan/features/settings/application/user_service.dart';

class _NoBiometrics extends BiometricService {
  @override
  Future<bool> available() async => false;
}

class Harness {
  Harness(this.container, this.db, this.business, this.owner);

  final ProviderContainer container;
  final AppDatabase db;
  final Business? business;
  final AppUser? owner;

  BusinessCtx get ctx => BusinessCtx(businessId: business!.id, userId: owner?.id);

  void setLanguage(AppLanguage l) => container.read(appPreferencesProvider.notifier).setLanguage(l);
}

/// Pumps the whole app on a typical small phone with an in-memory DB.
Future<Harness> pumpApp(
  WidgetTester tester, {
  bool onboarded = true,
  bool locked = false,
  AppLanguage language = AppLanguage.romanUrdu,
  ThemeMode theme = ThemeMode.light,
  Future<void> Function(AppDatabase db, BusinessCtx ctx)? seed,
  PinGate? pinGate,
  Size size = const Size(1080, 2280),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  PinService.useIsolate = false;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
  Business? business;
  AppUser? owner;
  await tester.runAsync(() async {
    if (onboarded) {
      business = await BusinessSetupService(db).createBusiness(name: 'Madina Mobiles', ownerName: 'Ali');
      final users = UserService(db, businessId: business!.id);
      final id = await users.createUser(name: 'Ali', role: UserRole.owner, pin: '1234');
      owner = (await users.activeUsers()).firstWhere((u) => u.id == id);
      await SettingsRepository(db).set(SettingKeys.lastBackupAt, DateTime.now().toIso8601String());
      if (seed != null) await seed(db, BusinessCtx(businessId: business!.id, userId: id));
    }
  });

  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(db),
    keyStoreProvider.overrideWithValue(MemoryKeyStore()),
    appDirProvider.overrideWithValue(Directory.systemTemp),
    initialPreferencesProvider.overrideWithValue(AppPreferences(language: language, themeMode: theme)),
    initialSessionProvider.overrideWithValue(Session(business: business, user: locked ? null : owner, locked: locked || !onboarded)),
    pinGateProvider.overrideWithValue(pinGate ?? const AlwaysAllowPinGate()),
    biometricServiceProvider.overrideWithValue(_NoBiometrics()),
    proActiveProvider.overrideWith((ref) async => true),
  ]);
  addTearDown(() async {
    container.dispose();
    await tester.runAsync(db.close);
  });

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SmartDukanApp()));
  await settle(tester);
  return Harness(container, db, business, owner);
}

/// pumpAndSettle that also lets real async DB work finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}
