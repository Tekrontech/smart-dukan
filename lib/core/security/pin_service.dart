import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'crypto.dart';

/// PIN hashing (spec Section 9: 4–6 digit PIN, slow KDF and salt).
///
/// Format: `pbkdf2-sha256$<iterations>$<salt b64>$<hash b64>`. The
/// iteration count is stored so it can be raised later without breaking
/// existing PINs.
class PinService {
  PinService._();

  static const int iterations = 30000;

  /// Off the UI thread in the app; widget tests set this to false because
  /// isolates do not run under the test's fake clock.
  static bool useIsolate = true;

  static Future<List<int>> _run((String, List<int>, int) a) => useIsolate ? compute(_derive, a) : _derive(a);

  static bool isValidFormat(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  /// Runs off the UI thread.
  static Future<String> hash(String pin, {int iterations = iterations}) async {
    if (!isValidFormat(pin)) throw ArgumentError('PIN must be 4–6 digits');
    final salt = Crypto.randomBytes(16);
    final h = await _run((pin, salt, iterations));
    return 'pbkdf2-sha256\$$iterations\$${base64.encode(salt)}\$${base64.encode(h)}';
  }

  static Future<bool> verify(String pin, String stored) async {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
    final it = int.tryParse(parts[1]);
    if (it == null) return false;
    final salt = base64.decode(parts[2]);
    final expected = base64.decode(parts[3]);
    final h = await _run((pin, salt, it));
    return Crypto.equalBytes(h, expected);
  }

  static Future<List<int>> _derive((String, List<int>, int) a) => Crypto.pbkdf2(a.$1, a.$2, a.$3);
}
