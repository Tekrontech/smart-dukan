import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Android Keystore-backed secret storage (spec Section 9). Abstracted so
/// tests can use [MemoryKeyStore].
abstract class SecureKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyStore implements SecureKeyStore {
  FlutterSecureKeyStore() : _s = const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryKeyStore implements SecureKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Names of the secrets we keep.
class SecretKeys {
  SecretKeys._();

  static const dbKey = 'db_key_v1';
  static const photoKey = 'photo_key_v1';
  static const installId = 'install_id_v1';
  static const license = 'license_v1';
}
