import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/db/app_database.dart';
import '../../../core/db/db_open.dart';
import '../../../core/db/migrations/migrations.dart';
import '../../../core/security/crypto.dart';
import '../../../core/security/key_store.dart';
import '../../../core/utils/fmt.dart';

enum BackupError { wrongPassword, notABackup, corrupt, newerVersion }

class BackupException implements Exception {
  const BackupException(this.error);

  final BackupError error;

  @override
  String toString() => 'BackupException(${error.name})';
}

/// What a backup file contains once decrypted.
class BackupContents {
  const BackupContents({required this.manifest, required this.dbBytes, required this.photos});

  final Map<String, dynamic> manifest;
  final Uint8List dbBytes;
  final Map<String, Uint8List> photos;

  int get schemaVersion => manifest['schemaVersion'] as int;
  String get shopName => manifest['shop'] as String? ?? '';
  DateTime get createdAt => DateTime.parse(manifest['createdAt'] as String);
  String get dbKey => manifest['dbKey'] as String;
  String? get photoKey => manifest['photoKey'] as String?;
}

/// Full encrypted backup and restore (spec Section 9).
///
/// `SmartDukan_<shop>_<yyyyMMdd_HHmm>.sdbk` = zip(manifest, DB snapshot,
/// photos) encrypted with AES-256-GCM using a key derived from the user's
/// backup password (PBKDF2-SHA256). Lost password = lost backup.
///
/// File layout: "SDBK" | version(1) | iterations(4, BE) | salt(16) |
/// nonce(12) | ciphertext | mac(16). The header is authenticated (AAD).
class BackupService {
  BackupService({required this.db, required this.dbFile, required this.photosDir, required this.keyStore});

  final AppDatabase db;
  final File dbFile;
  final Directory photosDir;
  final SecureKeyStore keyStore;

  static const _magic = [0x53, 0x44, 0x42, 0x4B]; // SDBK
  static const _version = 1;
  static const int kdfIterations = 120000;

  static String fileName(String shop, DateTime at) {
    final safe = shop.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return 'SmartDukan_${safe.isEmpty ? 'Shop' : safe}_${Fmt.fileStamp(at)}.sdbk';
  }

  /// Builds the encrypted backup bytes.
  Future<Uint8List> create({required String password, required String shopName, DateTime? now}) async {
    if (password.length < 6) throw ArgumentError('password too short');
    final at = now ?? DateTime.now();
    final tmpDir = await Directory.systemTemp.createTemp('sdbk');
    try {
      final snap = File(p.join(tmpDir.path, 'db.sqlite'));
      await db.customStatement("VACUUM INTO '${snap.path.replaceAll("'", "''")}'");
      final dbBytes = await snap.readAsBytes();

      final archive = Archive();
      final manifest = {
        'format': _version,
        'app': 'smart_dukan',
        'schemaVersion': DbMigrations.latestVersion,
        'createdAt': at.toIso8601String(),
        'shop': shopName,
        'dbKey': await keyStore.read(SecretKeys.dbKey),
        'photoKey': await keyStore.read(SecretKeys.photoKey),
      };
      final mBytes = utf8.encode(jsonEncode(manifest));
      archive.addFile(ArchiveFile('manifest.json', mBytes.length, mBytes));
      archive.addFile(ArchiveFile('db.sqlite', dbBytes.length, dbBytes));
      if (await photosDir.exists()) {
        await for (final f in photosDir.list()) {
          if (f is File) {
            final b = await f.readAsBytes();
            archive.addFile(ArchiveFile('photos/${p.basename(f.path)}', b.length, b));
          }
        }
      }
      final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);
      return await encryptBytes(zip, password);
    } finally {
      await tmpDir.delete(recursive: true);
    }
  }

  static Future<Uint8List> encryptBytes(Uint8List plain, String password, {int iterations = kdfIterations}) async {
    final salt = Crypto.randomBytes(16);
    final header = BytesBuilder()
      ..add(_magic)
      ..addByte(_version)
      ..add(_u32(iterations))
      ..add(salt);
    final h = header.toBytes();
    final key = await compute(_kdf, (password, salt, iterations));
    final body = await Crypto.encrypt(plain, key, aad: h);
    return Uint8List.fromList([...h, ...body]);
  }

  static Future<Uint8List> decryptBytes(Uint8List data, String password) async {
    if (data.length < 4 + 1 + 4 + 16 + 28) throw const BackupException(BackupError.notABackup);
    for (var i = 0; i < 4; i++) {
      if (data[i] != _magic[i]) throw const BackupException(BackupError.notABackup);
    }
    if (data[4] != _version) throw const BackupException(BackupError.newerVersion);
    final iterations = (data[5] << 24) | (data[6] << 16) | (data[7] << 8) | data[8];
    if (iterations < 1000 || iterations > 10000000) throw const BackupException(BackupError.corrupt);
    final salt = data.sublist(9, 25);
    final header = data.sublist(0, 25);
    final key = await compute(_kdf, (password, salt, iterations));
    try {
      return await Crypto.decrypt(data.sublist(25), key, aad: header);
    } catch (_) {
      // GCM cannot tell a wrong password from tampering; both are refused.
      throw const BackupException(BackupError.wrongPassword);
    }
  }

  /// Decrypts and checks a backup file: integrity, format and schema.
  static Future<BackupContents> read(Uint8List data, String password) async {
    final zipBytes = await decryptBytes(data, password);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    } catch (_) {
      throw const BackupException(BackupError.corrupt);
    }
    final mf = archive.findFile('manifest.json');
    final dbf = archive.findFile('db.sqlite');
    if (mf == null || dbf == null) throw const BackupException(BackupError.corrupt);
    final manifest = jsonDecode(utf8.decode(mf.content as List<int>)) as Map<String, dynamic>;
    if (manifest['app'] != 'smart_dukan' || manifest['dbKey'] == null) {
      throw const BackupException(BackupError.corrupt);
    }
    if ((manifest['schemaVersion'] as int) > DbMigrations.latestVersion) {
      throw const BackupException(BackupError.newerVersion);
    }
    final photos = <String, Uint8List>{};
    for (final f in archive.files) {
      if (f.isFile && f.name.startsWith('photos/')) {
        photos[p.basename(f.name)] = Uint8List.fromList(f.content as List<int>);
      }
    }
    return BackupContents(manifest: manifest, dbBytes: Uint8List.fromList(dbf.content as List<int>), photos: photos);
  }

  /// Replaces this phone's data with [contents]. The caller must close the
  /// open database first and make an automatic backup of current data
  /// (spec: "Before any restore: automatically back up current data").
  /// Older schemas are migrated when the restored DB is opened.
  static Future<void> install(BackupContents contents,
      {required File dbFile, required Directory photosDir, required SecureKeyStore keyStore}) async {
    // Verify the snapshot opens with its key before touching anything.
    final probe = File('${dbFile.path}.restore');
    await probe.writeAsBytes(contents.dbBytes, flush: true);
    final test = openEncryptedDatabase(probe, contents.dbKey, background: false);
    try {
      await test.customSelect('SELECT count(*) FROM businesses').get();
    } catch (_) {
      await test.close();
      await probe.delete();
      throw const BackupException(BackupError.corrupt);
    }
    await test.close();

    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('${dbFile.path}$suffix');
      if (await f.exists()) await f.delete();
    }
    await probe.rename(dbFile.path);
    await keyStore.write(SecretKeys.dbKey, contents.dbKey);
    if (contents.photoKey != null) await keyStore.write(SecretKeys.photoKey, contents.photoKey!);
    if (await photosDir.exists()) await photosDir.delete(recursive: true);
    await photosDir.create(recursive: true);
    for (final e in contents.photos.entries) {
      await File(p.join(photosDir.path, e.key)).writeAsBytes(e.value, flush: true);
    }
  }

  static Future<List<int>> _kdf((String, List<int>, int) a) => Crypto.pbkdf2(a.$1, a.$2, a.$3);

  static List<int> _u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
}
