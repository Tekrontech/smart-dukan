import 'dart:io';

import 'package:drift/native.dart';

import 'app_database.dart';

/// Opens the encrypted database file (spec Section 9).
///
/// Uses SQLite3MultipleCiphers in SQLCipher v4 mode with a raw 256-bit key
/// ([hexKey], 64 hex chars) kept in Android Keystore-backed secure storage.
/// A wrong key fails on the first query, never silently.
AppDatabase openEncryptedDatabase(File file, String hexKey, {bool background = true}) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey)) {
    throw ArgumentError('database key must be 64 lowercase hex chars');
  }
  void setup(dynamic raw) {
    raw.execute("PRAGMA cipher = 'sqlcipher';");
    raw.execute('PRAGMA legacy = 4;');
    raw.execute("PRAGMA hexkey = '$hexKey';");
    // Fail fast on a wrong key.
    raw.execute('SELECT count(*) FROM sqlite_master;');
    raw.execute('PRAGMA foreign_keys = ON;');
  }

  final executor = background
      ? NativeDatabase.createInBackground(file, setup: setup)
      : NativeDatabase(file, setup: setup);
  return AppDatabase(executor);
}
