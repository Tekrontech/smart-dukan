import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../../app/bootstrap.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/key_store.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../backup/presentation/restore_on_start.dart';

/// Shown when the database exists but cannot be opened (its Keystore key
/// is gone). Offers restoring a backup or starting fresh. Never deletes
/// anything without confirmation.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.keyStore, required this.dbFile});

  final SecureKeyStore keyStore;
  final File dbFile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('en', 'PK'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (context) {
        final l = context.l10n;
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Icon(Icons.key_off_rounded, size: 64, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: AppSpacing.md),
                  Text(l.keyLostTitle, style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.sm),
                  Text(l.keyLostBody, textAlign: TextAlign.center),
                  const Spacer(),
                  PrimaryButton(
                    label: l.restoreBackup,
                    icon: Icons.restore_rounded,
                    onPressed: () async {
                      final ok = await restoreOnStart(context, keyStore: keyStore, dbFile: dbFile);
                      if (ok) await bootstrap();
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(
                    label: l.startFresh,
                    outlined: true,
                    icon: Icons.restart_alt_rounded,
                    onPressed: () async {
                      final ok = await ConfirmSheet.show(
                        context,
                        title: l.startFresh,
                        message: l.startFreshConfirm,
                        confirmLabel: l.startFresh,
                        cancelLabel: l.cancel,
                        destructive: true,
                      );
                      if (!ok) return;
                      if (await dbFile.exists()) await dbFile.delete();
                      await keyStore.delete(SecretKeys.dbKey);
                      await bootstrap();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
