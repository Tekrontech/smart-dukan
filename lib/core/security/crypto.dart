import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Small crypto helpers on top of `package:cryptography` (spec Section 6:
/// Ed25519 verify, AES-GCM backups and photos).
class Crypto {
  Crypto._();

  static final Random _rng = Random.secure();

  static Uint8List randomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  static String toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List fromHex(String hex) {
    if (hex.length.isOdd) throw const FormatException('odd hex length');
    return Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
  }

  /// Constant-time comparison.
  static bool equalBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// PBKDF2-HMAC-SHA256.
  static Future<Uint8List> pbkdf2(String password, List<int> salt, int iterations, {int bits = 256}) async {
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: bits)
        .deriveKeyFromPassword(password: password, nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }

  static final AesGcm _aes = AesGcm.with256bits();

  /// AES-256-GCM. Output: nonce(12) | ciphertext | mac(16).
  static Future<Uint8List> encrypt(List<int> plain, List<int> key, {List<int> aad = const []}) async {
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key), nonce: _aes.newNonce(), aad: aad);
    return Uint8List.fromList(box.concatenation());
  }

  /// Throws [SecretBoxAuthenticationError] when the key is wrong or the data
  /// was altered.
  static Future<Uint8List> decrypt(List<int> data, List<int> key, {List<int> aad = const []}) async {
    final box = SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16);
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: SecretKey(key), aad: aad));
  }

  static Future<bool> verifyEd25519(List<int> message, List<int> signature, List<int> publicKey) =>
      Ed25519().verify(message, signature: Signature(signature, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)));

  static String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List fromB64url(String s) => base64Url.decode(base64Url.normalize(s));
}
