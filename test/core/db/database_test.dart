import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/core/db/db_open.dart';
import 'package:smart_dukan/core/db/migrations/migrations.dart';
import 'package:smart_dukan/features/onboarding/application/business_setup_service.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('fresh install creates every table, index and a migration record', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get();
    final names = tables.map((r) => r.read<String>('name')).toSet();
    for (final t in db.allTables) {
      expect(names, contains(t.actualTableName));
    }
    final idx = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get();
    expect(idx.length, greaterThanOrEqualTo(DbMigrations.indexes.length));
    final m = await db.select(db.schemaMigrations).get();
    expect(m.single.version, DbMigrations.latestVersion);
  });

  test('every upgrade step up to the latest version exists', () {
    for (var v = 2; v <= DbMigrations.latestVersion; v++) {
      expect(DbMigrations.steps.containsKey(v), isTrue, reason: 'missing step to v$v');
    }
  });

  test('seeding is idempotent and creates the chart of accounts', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final setup = BusinessSetupService(db);
    final b = await setup.createBusiness(name: 'Shop');
    final before = (await db.select(db.accounts).get()).length;
    await setup.seed(b.id);
    await setup.createBusiness(name: 'Again');
    expect((await db.select(db.accounts).get()).length, before);
    expect(await db.select(db.businesses).get(), hasLength(1));
    expect(await db.select(db.expenseCategories).get(), hasLength(6));
  });

  test('database file is encrypted and needs the right key', () async {
    final dir = await Directory.systemTemp.createTemp('sd');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/shop.db');
    const key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

    final db = openEncryptedDatabase(file, key, background: false);
    await BusinessSetupService(db).createBusiness(name: 'Secret Mobiles');
    await db.close();

    final raw = await file.readAsBytes();
    expect(String.fromCharCodes(raw).contains('Secret Mobiles'), isFalse);
    expect(String.fromCharCodes(raw.take(15)), isNot('SQLite format 3'));

    final again = openEncryptedDatabase(file, key, background: false);
    expect((await again.select(again.businesses).getSingle()).name, 'Secret Mobiles');
    await again.close();

    final wrong = openEncryptedDatabase(file, 'f' * 64, background: false);
    await expectLater(wrong.select(wrong.businesses).get(), throwsA(anything));
    await wrong.close();
  });
}
