import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/ids.dart';
import 'crypto.dart';
import 'key_store.dart';
import 'license_public_key.dart';

/// Packs that can be unlocked.
class Packs {
  Packs._();

  static const mobilePro = 'mobile_pro';
  static const all = {mobilePro};
}

enum LicenseError { malformed, badSignature, wrongDevice, unknownPack }

class LicenseException implements Exception {
  const LicenseException(this.error);

  final LicenseError error;

  @override
  String toString() => 'LicenseException(${error.name})';
}

/// A verified activation code.
class LicenseCode {
  const LicenseCode({
    required this.deviceCode,
    required this.pack,
    required this.issuedDate,
    required this.licenseId,
    required this.signature,
    required this.raw,
  });

  final String deviceCode;
  final String pack;
  final String issuedDate;
  final String licenseId;
  final String signature;
  final String raw;
}

/// Offline licensing (spec Section 2).
///
/// Device Code = the 128-bit install ID in Crockford base32 (26 chars),
/// grouped in fives. The seller signs `SD1|deviceCode|pack|issuedDate|licenseId`
/// with an Ed25519 private key (`tools/license_gen.dart`); the app verifies
/// with the embedded public key. Activation code =
/// `base64url(payload) + "." + base64url(signature)`, delivered as
/// `smartdukan://activate?c=<code>` or a QR.
///
/// Licence checks never touch business records: without Pro, Pro records
/// stay readable and exportable.
class LicenseService {
  LicenseService({required this.db, required this.keyStore, required this.installId, List<int>? publicKey})
      : publicKey = publicKey ?? licensePublicKey;

  final AppDatabase db;
  final SecureKeyStore keyStore;
  final String installId;
  final List<int> publicKey;

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Crockford base32 of the 16 install-id bytes: 26 characters.
  static String deviceCodeFor(String installId) {
    final hex = installId.replaceAll('-', '');
    if (hex.length != 32) throw ArgumentError('install id must be a UUID');
    var value = BigInt.parse(hex, radix: 16);
    final chars = List.filled(26, '0');
    for (var i = 25; i >= 0; i--) {
      chars[i] = _alphabet[(value & BigInt.from(31)).toInt()];
      value = value >> 5;
    }
    return chars.join();
  }

  /// `K7QM2-XPA9D-...` (never truncated).
  static String group(String code) {
    final clean = normalize(code);
    final parts = <String>[];
    for (var i = 0; i < clean.length; i += 5) {
      parts.add(clean.substring(i, i + 5 > clean.length ? clean.length : i + 5));
    }
    return parts.join('-');
  }

  /// Uppercase, no separators, Crockford look-alikes fixed (O→0, I/L→1).
  static String normalize(String code) => code
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');

  String get deviceCode => deviceCodeFor(installId);

  static String payloadOf({required String deviceCode, required String pack, required String issuedDate, required String licenseId}) =>
      'SD1|${normalize(deviceCode)}|$pack|$issuedDate|$licenseId';

  /// Accepts the bare code or the whole `smartdukan://activate?c=` link.
  static String extractCode(String input) {
    final t = input.trim();
    final uri = Uri.tryParse(t);
    if (uri != null && uri.queryParameters['c'] != null) return uri.queryParameters['c']!;
    return t;
  }

  /// Parses and verifies a code for THIS device. Throws [LicenseException].
  Future<LicenseCode> verify(String input) async {
    final raw = extractCode(input);
    final dot = raw.indexOf('.');
    if (dot <= 0) throw const LicenseException(LicenseError.malformed);
    Uint8List payloadBytes, sig;
    try {
      payloadBytes = Crypto.fromB64url(raw.substring(0, dot));
      sig = Crypto.fromB64url(raw.substring(dot + 1));
    } catch (_) {
      throw const LicenseException(LicenseError.malformed);
    }
    final payload = utf8.decode(payloadBytes, allowMalformed: true);
    final parts = payload.split('|');
    if (parts.length != 5 || parts[0] != 'SD1' || sig.length != 64) {
      throw const LicenseException(LicenseError.malformed);
    }
    final ok = await Crypto.verifyEd25519(payloadBytes, sig, publicKey);
    if (!ok) throw const LicenseException(LicenseError.badSignature);
    if (parts[1] != normalize(deviceCode)) throw const LicenseException(LicenseError.wrongDevice);
    if (!Packs.all.contains(parts[2])) throw const LicenseException(LicenseError.unknownPack);
    return LicenseCode(
      deviceCode: parts[1],
      pack: parts[2],
      issuedDate: parts[3],
      licenseId: parts[4],
      signature: raw.substring(dot + 1),
      raw: raw,
    );
  }

  /// Verifies and stores a code (secure storage + database).
  Future<LicenseCode> activate(String input) async {
    final code = await verify(input);
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.delete(db.licenses)..where((l) => l.pack.equals(code.pack) & l.deviceCode.equals(code.deviceCode))).go();
      final business = await (db.select(db.businesses)..limit(1)).getSingleOrNull();
      await db.into(db.licenses).insert(LicensesCompanion.insert(
            id: newId(),
            businessId: business?.id ?? '',
            createdAt: now,
            updatedAt: now,
            pack: code.pack,
            deviceCode: code.deviceCode,
            licenseId: code.licenseId,
            issuedAt: DateTime.tryParse(code.issuedDate) ?? now,
            signature: code.signature,
            code: code.raw,
            status: LicenseStatus.active,
          ));
      await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
            id: newId(),
            businessId: business?.id ?? '',
            createdAt: now,
            updatedAt: now,
            entity: 'license',
            entityId: code.licenseId,
            action: 'activate',
            afterJson: Value(jsonEncode({'pack': code.pack})),
          ));
    });
    await keyStore.write('${SecretKeys.license}_${code.pack}', code.raw);
    return code;
  }

  /// Whether [pack] is unlocked on this device. Re-verifies the stored code,
  /// so a tampered row or a restored backup from another phone is inactive.
  Future<bool> isActive(String pack) async {
    final rows = await (db.select(db.licenses)
          ..where((l) => l.pack.equals(pack) & l.status.equalsValue(LicenseStatus.active)))
        .get();
    final candidates = [...rows.map((r) => r.code), ?(await keyStore.read('${SecretKeys.license}_$pack'))];
    for (final c in candidates) {
      try {
        final v = await verify(c);
        if (v.pack == pack) return true;
      } on LicenseException {
        continue;
      }
    }
    return false;
  }

  /// Licences stored in the DB that belong to another device (restored
  /// backup / new phone): used to build the Transfer request.
  Future<List<LicenseRow>> foreignLicenses() async {
    final mine = normalize(deviceCode);
    return (await db.select(db.licenses).get()).where((l) => l.deviceCode != mine).toList();
  }
}
