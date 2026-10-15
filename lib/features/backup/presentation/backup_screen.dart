import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/bootstrap.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/pin_gate.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/files.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/backup_service.dart';
import 'backup_dialogs.dart';

/// Encrypted backup and restore (spec Section 9). Owner PIN required.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  DateTime? _last;
  Uint8List? _ready;
  String? _readyName;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    final v = await ref.read(settingsRepoProvider).get(SettingKeys.lastBackupAt);
    if (mounted) setState(() => _last = v == null ? null : DateTime.tryParse(v));
  }

  BackupService _service() {
    final dir = ref.read(appDirProvider);
    return BackupService(
      db: ref.read(databaseProvider),
      dbFile: File(p.join(dir.path, dbFileName)),
      photosDir: Directory(p.join(dir.path, 'photos')),
      keyStore: ref.read(keyStoreProvider),
    );
  }

  Future<void> _backup() async {
    if (!await ref.read(pinGateProvider).requireOwner(context)) return;
    if (!mounted) return;
    final password = await askBackupPassword(context, confirm: true);
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    final business = ref.read(sessionProvider).business!;
    final now = DateTime.now();
    final bytes = await guard(context, () => _service().create(password: password, shopName: business.name, now: now));
    if (!mounted) return;
    setState(() => _busy = false);
    if (bytes == null) return;
    await ref.read(settingsRepoProvider).set(SettingKeys.lastBackupAt, now.toIso8601String(), businessId: business.id);
    if (!mounted) return;
    setState(() {
      _ready = bytes;
      _readyName = BackupService.fileName(business.name, now);
      _last = now;
    });
    showMessage(context, context.l10n.backupCreated);
  }

  Future<void> _restore() async {
    final l = context.l10n;
    if (!await ref.read(pinGateProvider).requireOwner(context)) return;
    if (!mounted) return;
    final go = await ConfirmSheet.show(context,
        title: l.restoreTitle, message: l.restoreWarning, confirmLabel: l.chooseBackupFile, cancelLabel: l.cancel, destructive: true);
    if (!go || !mounted) return;
    final bytes = await pickBackupFile();
    if (bytes == null || !mounted) return;
    final password = await askBackupPassword(context);
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final contents = await BackupService.read(bytes, password);
      if (!mounted) return;
      setState(() => _busy = false);
      final sure = await ConfirmSheet.show(context,
          title: l.restoreTitle,
          message: l.restoreFrom(contents.shopName, Fmt.dateTime(contents.createdAt)),
          confirmLabel: l.restoreBackup,
          cancelLabel: l.cancel,
          destructive: true);
      if (!sure || !mounted) return;
      setState(() => _busy = true);

      // Spec: back up current data automatically before any restore.
      final dir = ref.read(appDirProvider);
      final auto = Directory(p.join(dir.path, 'auto_backups'));
      await auto.create(recursive: true);
      final business = ref.read(sessionProvider).business!;
      final safety = await _service().create(password: password, shopName: business.name);
      await File(p.join(auto.path, BackupService.fileName('before_restore_${business.name}', DateTime.now())))
          .writeAsBytes(safety, flush: true);

      final db = ref.read(databaseProvider);
      await db.close();
      await BackupService.install(contents,
          dbFile: File(p.join(dir.path, dbFileName)),
          photosDir: Directory(p.join(dir.path, 'photos')),
          keyStore: ref.read(keyStoreProvider));
      if (mounted) showMessage(context, l.restoreDone);
      await bootstrap(); // reopen the app on the restored data (migrates if older)
    } on BackupException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, backupErrorText(context, e.error));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final stale = _last == null || DateTime.now().difference(_last!) > const Duration(days: 7);
    return Scaffold(
      appBar: AppBar(title: Text(l.backupRestore)),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Card(
              child: ListTile(
                leading: Icon(stale ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                    color: stale ? c.warning : c.success),
                title: Text(_last == null ? l.neverBackedUp : l.lastBackup(Fmt.dateTime(_last!))),
                subtitle: stale ? Text(l.backupReminder) : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l.backupWarning, style: theme.textTheme.bodyMedium?.copyWith(color: c.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(label: l.backupNow, icon: Icons.backup_rounded, loading: _busy, onPressed: _backup),
            if (_ready != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_readyName!, style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: l.saveToPhone,
                icon: Icons.save_alt_rounded,
                outlined: true,
                onPressed: () => guard(context, () => saveBytesAs(_readyName!, _ready!)),
              ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: l.shareBackup,
                icon: Icons.share_rounded,
                outlined: true,
                onPressed: () => guard(context, () => shareBytes(_readyName!, _ready!)),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
            Text(l.restoreTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(l.restoreWarning, style: theme.textTheme.bodyMedium?.copyWith(color: c.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(label: l.restoreBackup, icon: Icons.restore_rounded, outlined: true, onPressed: _restore),
          ],
        ),
      ),
    );
  }
}
