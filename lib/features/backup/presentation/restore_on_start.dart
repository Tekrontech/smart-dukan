import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/l10n/l10n.dart';
import '../../../core/security/key_store.dart';
import '../../../core/widgets/feedback.dart';
import '../application/backup_service.dart';
import 'backup_dialogs.dart';

/// Restore when the app cannot open its own database (no data to keep).
Future<bool> restoreOnStart(BuildContext context, {required SecureKeyStore keyStore, required File dbFile}) async {
  final bytes = await pickBackupFile();
  if (bytes == null || !context.mounted) return false;
  final password = await askBackupPassword(context);
  if (password == null || !context.mounted) return false;
  try {
    final contents = await BackupService.read(bytes, password);
    await BackupService.install(contents,
        dbFile: dbFile, photosDir: Directory(p.join(dbFile.parent.path, 'photos')), keyStore: keyStore);
    if (context.mounted) showMessage(context, context.l10n.restoreDone);
    return true;
  } on BackupException catch (e) {
    if (context.mounted) showMessage(context, backupErrorText(context, e.error));
    return false;
  }
}
