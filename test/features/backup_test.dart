import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/accounting/health_check.dart';
import 'package:smart_dukan/core/accounting/ledger_queries.dart';
import 'package:smart_dukan/core/accounting/system_accounts.dart';
import 'package:smart_dukan/core/db/db_open.dart';
import 'package:smart_dukan/core/security/key_store.dart';
import 'package:smart_dukan/core/security/photo_vault.dart';
import 'package:smart_dukan/features/backup/application/backup_service.dart';
import 'package:smart_dukan/features/onboarding/application/business_setup_service.dart';
import 'package:smart_dukan/features/onboarding/application/demo_data_service.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('backup, wipe app, restore: every balance identical; photos come back', () async {
    final dir = await Directory.systemTemp.createTemp('sdb');
    addTearDown(() => dir.delete(recursive: true));
    final dbFile = File('${dir.path}/shop.db');
    final photos = Directory('${dir.path}/photos');
    final keys = MemoryKeyStore();
    const key = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    await keys.write(SecretKeys.dbKey, key);

    var db = openEncryptedDatabase(dbFile, key, background: false);
    final b = await BusinessSetupService(db).createBusiness(name: 'Al-Madina Mobiles');
    await DemoDataService(db, businessId: b.id, clock: () => DateTime(2026, 10, 15, 18)).load();
    final vault = PhotoVault(dir: photos, keyStore: keys);
    final photoName = await vault.save(Uint8List.fromList(List.generate(500, (i) => i % 256)));

    Future<Map<String, int>> snapshot() async {
      final q = LedgerQueries(db);
      return {
        for (final a in SysAccount.values) a.key: (await q.sysBalance(a)).paisa,
        'parties': (await db.select(db.parties).get()).length,
        'sales': (await db.select(db.sales).get()).length,
      };
    }

    final before = await snapshot();
    final bytes = await BackupService(db: db, dbFile: dbFile, photosDir: photos, keyStore: keys)
        .create(password: 'secret123', shopName: b.name);
    expect(String.fromCharCodes(bytes).contains('Al-Madina'), isFalse);
    expect(BackupService.fileName('Al-Madina Mobiles', DateTime(2026, 10, 15, 9, 5)),
        'SmartDukan_Al_Madina_Mobiles_20261015_0905.sdbk');

    await expectLater(BackupService.read(bytes, 'wrong-pass'),
        throwsA(isA<BackupException>().having((e) => e.error, 'error', BackupError.wrongPassword)));
    final tampered = Uint8List.fromList(bytes)..[bytes.length - 40] ^= 0xff;
    await expectLater(BackupService.read(tampered, 'secret123'), throwsA(isA<BackupException>()));
    await expectLater(BackupService.read(Uint8List.fromList(List.filled(100, 7)), 'secret123'),
        throwsA(isA<BackupException>().having((e) => e.error, 'error', BackupError.notABackup)));

    // "Wipe app": close and delete everything, including the keys.
    await db.close();
    await dbFile.delete();
    await photos.delete(recursive: true);
    final freshKeys = MemoryKeyStore();

    final contents = await BackupService.read(bytes, 'secret123');
    expect(contents.shopName, 'Al-Madina Mobiles');
    await BackupService.install(contents, dbFile: dbFile, photosDir: photos, keyStore: freshKeys);
    db = openEncryptedDatabase(dbFile, (await freshKeys.read(SecretKeys.dbKey))!, background: false);
    addTearDown(db.close);
    expect(await snapshot(), before);
    expect(await HealthCheck(db).run(), isEmpty);
    final restoredPhoto = await PhotoVault(dir: photos, keyStore: freshKeys).read(photoName);
    expect(restoredPhoto, hasLength(500));
  });
}
