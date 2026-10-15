import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/db/app_database.dart';
import 'package:smart_dukan/core/security/crypto.dart';
import 'package:smart_dukan/core/security/key_store.dart';
import 'package:smart_dukan/core/security/license_service.dart';
import 'package:smart_dukan/core/security/pin_service.dart';

void main() {
  late SimpleKeyPair pair;
  late List<int> pub;
  const install = '7f1c2a3b-4d5e-4f60-8a1b-2c3d4e5f6a7b';
  const otherInstall = '00000000-1111-4222-8333-444455556666';

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    pair = await Ed25519().newKeyPair();
    pub = (await pair.extractPublicKey()).bytes;
  });

  Future<String> sign(String device, {String pack = Packs.mobilePro, String id = 'L-1'}) async {
    final payload = LicenseService.payloadOf(deviceCode: device, pack: pack, issuedDate: '2026-10-15', licenseId: id);
    final sig = await Ed25519().sign(utf8.encode(payload), keyPair: pair);
    return '${Crypto.b64url(utf8.encode(payload))}.${Crypto.b64url(sig.bytes)}';
  }

  LicenseService svc(AppDatabase db, String installId, [SecureKeyStore? keys]) =>
      LicenseService(db: db, keyStore: keys ?? MemoryKeyStore(), installId: installId, publicKey: pub);

  test('device code is the full install id in Crockford base32, grouped in fives', () {
    final code = LicenseService.deviceCodeFor(install);
    expect(code, hasLength(26));
    expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]+$').hasMatch(code), isTrue);
    final grouped = LicenseService.group(code);
    expect(grouped.split('-').map((g) => g.length), [5, 5, 5, 5, 5, 1]);
    expect(LicenseService.normalize(grouped.toLowerCase()), code);
    expect(LicenseService.deviceCodeFor(otherInstall), isNot(code));
  });

  test('valid code unlocks Pro; link form accepted; tampered and wrong-device codes rejected', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final s = svc(db, install);
    expect(await s.isActive(Packs.mobilePro), isFalse);

    final good = await sign(s.deviceCode);
    await s.activate('smartdukan://activate?c=$good');
    expect(await s.isActive(Packs.mobilePro), isTrue);

    final tampered = good.replaceRange(5, 6, good[5] == 'A' ? 'B' : 'A');
    await expectLater(s.verify(tampered), throwsA(isA<LicenseException>()));

    final otherDevice = await sign(LicenseService.deviceCodeFor(otherInstall));
    await expectLater(s.verify(otherDevice),
        throwsA(isA<LicenseException>().having((e) => e.error, 'error', LicenseError.wrongDevice)));

    final otherKey = await Ed25519().newKeyPair();
    final payload = LicenseService.payloadOf(
        deviceCode: s.deviceCode, pack: Packs.mobilePro, issuedDate: '2026-10-15', licenseId: 'X');
    final forged = await Ed25519().sign(utf8.encode(payload), keyPair: otherKey);
    await expectLater(s.verify('${Crypto.b64url(utf8.encode(payload))}.${Crypto.b64url(forged.bytes)}'),
        throwsA(isA<LicenseException>().having((e) => e.error, 'error', LicenseError.badSignature)));
    await expectLater(s.verify('not-a-code'), throwsA(isA<LicenseException>()));
  });

  test('restored on another phone: data readable but Pro inactive until re-activation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await svc(db, install).activate(await sign(LicenseService.deviceCodeFor(install)));
    final onNewPhone = svc(db, otherInstall);
    expect(await onNewPhone.isActive(Packs.mobilePro), isFalse);
    expect(await onNewPhone.foreignLicenses(), hasLength(1));
    await onNewPhone.activate(await sign(onNewPhone.deviceCode, id: 'L-2'));
    expect(await onNewPhone.isActive(Packs.mobilePro), isTrue);
  });

  test('PIN hash: slow KDF with salt, verifies only the right PIN', () async {
    final h1 = await PinService.hash('1234');
    final h2 = await PinService.hash('1234');
    expect(h1, isNot(h2)); // random salt
    expect(h1.startsWith('pbkdf2-sha256\$30000\$'), isTrue);
    expect(await PinService.verify('1234', h1), isTrue);
    expect(await PinService.verify('4321', h1), isFalse);
    expect(PinService.isValidFormat('12'), isFalse);
    expect(PinService.isValidFormat('123456'), isTrue);
  });
}
