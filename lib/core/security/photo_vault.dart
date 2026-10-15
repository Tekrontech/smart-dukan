import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../utils/ids.dart';
import 'crypto.dart';
import 'key_store.dart';

/// Encrypted photo storage (spec Section 9): CNIC, bills and device photos
/// are AES-256-GCM encrypted with a Keystore-held key and saved only in
/// app-private storage. They never touch the gallery or cache in plain form.
class PhotoVault {
  PhotoVault({required this.dir, required this.keyStore});

  final Directory dir;
  final SecureKeyStore keyStore;

  Future<List<int>> _key() async {
    var hex = await keyStore.read(SecretKeys.photoKey);
    if (hex == null) {
      hex = Crypto.toHex(Crypto.randomBytes(32));
      await keyStore.write(SecretKeys.photoKey, hex);
    }
    return Crypto.fromHex(hex);
  }

  /// Encrypts and stores [bytes]; returns the file name to keep in the DB.
  Future<String> save(Uint8List bytes) async {
    await dir.create(recursive: true);
    final name = '${newId()}.enc';
    final data = await Crypto.encrypt(bytes, await _key(), aad: name.codeUnits);
    await File(p.join(dir.path, name)).writeAsBytes(data, flush: true);
    return name;
  }

  Future<Uint8List?> read(String name) async {
    final f = File(p.join(dir.path, p.basename(name)));
    if (!await f.exists()) return null;
    try {
      return await Crypto.decrypt(await f.readAsBytes(), await _key(), aad: p.basename(name).codeUnits);
    } catch (_) {
      return null;
    }
  }

  /// Overwrites then deletes the file (retention / on request).
  Future<void> shred(String name) async {
    final f = File(p.join(dir.path, p.basename(name)));
    if (!await f.exists()) return;
    final len = await f.length();
    await f.writeAsBytes(Uint8List(len), flush: true);
    await f.delete();
  }
}
