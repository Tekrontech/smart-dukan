import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/ids.dart';

/// Keys stored in the encrypted `app_settings` table.
class SettingKeys {
  SettingKeys._();

  static const language = 'language';
  static const theme = 'theme';
  static const urduDigits = 'urdu_digits';
  static const allowNegativeStock = 'allow_negative_stock';
  static const autoLockMinutes = 'auto_lock_minutes';
  static const biometric = 'biometric_enabled';
  static const lastUserId = 'last_user_id';
  static const installId = 'install_id';
  static const demoData = 'demo_data';
  static const coachShown = 'coach_shown';
  static const cnicEnabled = 'cnic_enabled';
  static const cnicRetentionMonths = 'cnic_retention_months';
  static const lastBackupAt = 'last_backup_at';
  static const exportWarningShown = 'export_warning_shown';
  static const taxEnabled = 'tax_enabled';
  static const playBilling = 'play_billing_enabled';
}

class SettingsRepository {
  SettingsRepository(this.db);

  final AppDatabase db;

  Future<String?> get(String key) async =>
      (await (db.select(db.appSettings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<Map<String, String>> all() async => {for (final s in await db.select(db.appSettings).get()) s.key: s.value};

  Stream<String?> watch(String key) =>
      (db.select(db.appSettings)..where((s) => s.key.equals(key))).watchSingleOrNull().map((s) => s?.value);

  Future<void> set(String key, String value, {String businessId = ''}) async {
    final now = DateTime.now();
    final existing = await (db.select(db.appSettings)..where((s) => s.key.equals(key))).getSingleOrNull();
    if (existing == null) {
      await db.into(db.appSettings).insert(AppSettingsCompanion.insert(
            id: newId(),
            businessId: businessId,
            createdAt: now,
            updatedAt: now,
            key: key,
            value: value,
          ));
    } else if (existing.value != value) {
      await (db.update(db.appSettings)..where((s) => s.id.equals(existing.id)))
          .write(AppSettingsCompanion(value: Value(value), updatedAt: Value(now)));
    }
  }

  Future<bool> getBool(String key, {bool fallback = false}) async {
    final v = await get(key);
    return v == null ? fallback : v == 'true';
  }

  Future<int> getInt(String key, {required int fallback}) async => int.tryParse(await get(key) ?? '') ?? fallback;
}
