import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/files.dart';
import '../application/backup_service.dart';

String backupErrorText(BuildContext context, BackupError e) {
  final l = context.l10n;
  return switch (e) {
    BackupError.wrongPassword => l.errWrongPassword,
    BackupError.notABackup => l.errNotBackup,
    BackupError.corrupt => l.errBackupCorrupt,
    BackupError.newerVersion => l.errBackupNewer,
  };
}

/// Asks for a backup password. With [confirm] the user types it twice and
/// sees the "lost password = lost backup" warning.
Future<String?> askBackupPassword(BuildContext context, {bool confirm = false}) {
  return showDialog<String>(context: context, builder: (_) => _PasswordDialog(confirm: confirm));
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.confirm});

  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _submit() {
    final l = context.l10n;
    if (_a.text.length < 6) {
      setState(() => _error = l.backupPasswordHint);
    } else if (widget.confirm && _a.text != _b.text) {
      setState(() => _error = l.passwordsDontMatch);
    } else {
      Navigator.of(context).pop(_a.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.backupPassword),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.confirm) ...[
              Text(l.backupWarning, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              controller: _a,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.backupPassword,
                helperText: l.backupPasswordHint,
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (widget.confirm) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _b,
                obscureText: _obscure,
                decoration: InputDecoration(labelText: l.backupPasswordConfirm),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        FilledButton(onPressed: _submit, child: Text(l.confirm)),
      ],
    );
  }
}

/// Lets the user pick a `.sdbk` file and returns its bytes.
Future<Uint8List?> pickBackupFile() => pickFileBytes();
