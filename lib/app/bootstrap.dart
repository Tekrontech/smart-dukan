import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/db/app_database.dart';
import '../core/db/db_open.dart';
import '../core/accounting/posting.dart';
import '../core/security/crypto.dart';
import '../core/security/key_store.dart';
import '../core/security/photo_vault.dart';
import '../core/settings/app_preferences.dart';
import '../core/settings/settings_repository.dart';
import '../core/utils/ids.dart';
import '../features/onboarding/application/business_setup_service.dart';
import '../features/pro_mobile/used_phones/application/used_phone_service.dart';
import '../features/settings/presentation/startup_error_app.dart';
import 'app.dart';
import 'providers.dart';

/// Database file name inside app-private storage.
const dbFileName = 'smart_dukan.db';

Future<File> databaseFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, dbFileName));
}

/// App start-up: open the encrypted database with the Keystore key, read
/// the install ID, load preferences and the shop, then show onboarding or
/// the lock screen (spec Sections 2 and 9).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final keys = FlutterSecureKeyStore();
  final file = await databaseFile();

  var dbKey = await keys.read(SecretKeys.dbKey);
  if (dbKey == null) {
    if (await file.exists()) {
      // The database exists but its key is gone (secure storage wiped).
      // It cannot be read; only a backup can bring the data back.
      runApp(StartupErrorApp(keyStore: keys, dbFile: file));
      return;
    }
    dbKey = Crypto.toHex(Crypto.randomBytes(32));
    await keys.write(SecretKeys.dbKey, dbKey);
  }

  final AppDatabase db;
  try {
    db = openEncryptedDatabase(file, dbKey);
    await db.customSelect('SELECT 1').get();
  } catch (_) {
    runApp(StartupErrorApp(keyStore: keys, dbFile: file));
    return;
  }

  final settings = SettingsRepository(db);
  final secureInstall = await keys.read(SecretKeys.installId);
  final dbInstall = await settings.get(SettingKeys.installId);
  var installId = secureInstall ?? dbInstall;
  var mismatch = false;
  if (installId == null) {
    installId = newRandomId();
    await keys.write(SecretKeys.installId, installId);
    await settings.set(SettingKeys.installId, installId);
  } else {
    if (secureInstall == null) await keys.write(SecretKeys.installId, installId);
    if (dbInstall == null) await settings.set(SettingKeys.installId, installId);
    mismatch = secureInstall != null && dbInstall != null && secureInstall != dbInstall;
  }

  final prefs = AppPreferences.fromSettings(await settings.all());
  final business = await BusinessSetupService(db).currentBusiness();

  // CNIC retention (spec 9): purge seller identity data of phones sold more
  // than N months ago. Never blocks start-up.
  if (business != null) {
    try {
      final months = await settings.getInt(SettingKeys.cnicRetentionMonths, fallback: 12);
      final vault = PhotoVault(dir: Directory(p.join(file.parent.path, 'photos')), keyStore: keys);
      await UsedPhoneService(db, BusinessCtx(businessId: business.id)).purgeExpiredIdentity(months: months, shred: vault.shred);
    } catch (_) {}
  }

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      keyStoreProvider.overrideWithValue(keys),
      appDirProvider.overrideWithValue(file.parent),
      startupInfoProvider.overrideWithValue(StartupInfo(installId: installId, installIdMismatch: mismatch)),
      initialPreferencesProvider.overrideWithValue(prefs),
      initialSessionProvider.overrideWithValue(Session(business: business, locked: true)),
    ],
    child: const SmartDukanApp(),
  ));
}
