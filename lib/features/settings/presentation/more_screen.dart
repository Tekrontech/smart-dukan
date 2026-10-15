import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/settings/app_preferences.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/utils/fmt.dart';
import '../../onboarding/application/demo_data_service.dart';

/// More / Settings (spec 5.11).
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static const String appVersion = '1.0.0';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final prefs = ref.watch(appPreferencesProvider);
    final notifier = ref.read(appPreferencesProvider.notifier);
    final session = ref.watch(sessionProvider);
    final can = session.can;
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final demo = ref.watch(_demoProvider).value ?? false;
    final lastBackup = ref.watch(_lastBackupProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: c.primaryContainer,
                  child: Icon(Icons.storefront_rounded, color: c.primary),
                ),
                title: Text(session.business?.name ?? l.appTitle, style: theme.textTheme.titleMedium),
                subtitle: Text(l.loggedInAs(session.user?.name ?? '-', roleLabel(context, session.user?.role))),
                trailing: IconButton(
                  key: const Key('lock_now'),
                  tooltip: l.lockNow,
                  icon: const Icon(Icons.lock_outline_rounded),
                  onPressed: () => ref.read(sessionProvider.notifier).lock(),
                ),
              ),
            ),
          ),
          if (demo && can.settings)
            _Tile(
              icon: Icons.cleaning_services_outlined,
              title: l.wipeDemo,
              color: c.danger,
              onTap: () async {
                final ok = await ConfirmSheet.show(context,
                    title: l.wipeDemo,
                    message: l.wipeDemoBody,
                    confirmLabel: l.wipeDemo,
                    cancelLabel: l.cancel,
                    destructive: true);
                if (!ok || !context.mounted) return;
                final s = ref.read(sessionProvider);
                await guard(context, () => DemoDataService(ref.read(databaseProvider), businessId: s.business!.id, userId: s.user?.id).wipe());
                ref.invalidate(_demoProvider);
                if (context.mounted) showMessage(context, l.demoWiped);
              },
            ),
          _Header(l.sectionRecords),
          if (can.reports) _Tile(icon: Icons.bar_chart_rounded, title: l.reports, onTap: () => context.push(Routes.reports)),
          _Tile(icon: Icons.receipt_long_outlined, title: l.salesList, onTap: () => context.push(Routes.salesList)),
          if (can.purchase)
            _Tile(icon: Icons.shopping_cart_outlined, title: l.purchases, onTap: () => context.push(Routes.purchasesList)),
          if (can.expenses) _Tile(icon: Icons.payments_outlined, title: l.expenses, onTap: () => context.push(Routes.expensesList)),
          if (can.cashClosing) _Tile(icon: Icons.lock_clock_outlined, title: l.gallaBand, onTap: () => context.push(Routes.galla)),
          _Header(l.sectionPro),
          _Tile(icon: Icons.qr_code_scanner_rounded, title: l.imeiSearch, pro: true, onTap: () => context.push(Routes.imeiSearch)),
          if (can.repairs) _Tile(icon: Icons.build_outlined, title: l.repairJobs, pro: true, onTap: () => context.push(Routes.repairs)),
          if (can.qist) _Tile(icon: Icons.event_repeat_rounded, title: l.qistPlans, pro: true, onTap: () => context.push(Routes.qistList)),
          if (can.usedPhones)
            _Tile(icon: Icons.phone_android_rounded, title: l.usedPhones, pro: true, onTap: () => context.push(Routes.usedPhoneList)),
          if (can.settings) ...[
            _Header(l.sectionBusiness),
            _Tile(icon: Icons.store_outlined, title: l.shopProfile, onTap: () => context.push(Routes.shopProfile)),
            _Tile(icon: Icons.verified_outlined, title: l.licenseAndPro, onTap: () => context.push(Routes.license)),
          ],
          _Header(l.sectionDisplay),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.language, style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<AppLanguage>(
                  key: const Key('language_selector'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: AppLanguage.english, label: Text(l.languageEnglish)),
                    ButtonSegment(value: AppLanguage.romanUrdu, label: Text(l.languageRomanUrdu)),
                    ButtonSegment(value: AppLanguage.urdu, label: Text(l.languageUrdu)),
                  ],
                  selected: {prefs.language},
                  onSelectionChanged: (s) => notifier.setLanguage(s.first),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(l.theme, style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: ThemeMode.system, label: Text(l.themeSystem), icon: const Icon(Icons.brightness_auto_outlined)),
                    ButtonSegment(value: ThemeMode.light, label: Text(l.themeLight), icon: const Icon(Icons.light_mode_outlined)),
                    ButtonSegment(value: ThemeMode.dark, label: Text(l.themeDark), icon: const Icon(Icons.dark_mode_outlined)),
                  ],
                  selected: {prefs.themeMode},
                  onSelectionChanged: (s) => notifier.setThemeMode(s.first),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.urduDigits),
                  value: prefs.urduDigits,
                  onChanged: notifier.setUrduDigits,
                ),
              ],
            ),
          ),
          _Header(l.securitySection),
          _Tile(icon: Icons.password_rounded, title: l.securitySection, onTap: () => context.push(Routes.security)),
          if (can.staff) _Tile(icon: Icons.group_outlined, title: l.staffAndRoles, onTap: () => context.push(Routes.staff)),
          if (can.backup) ...[
            _Header(l.dataSection),
            _Tile(
              icon: Icons.backup_outlined,
              title: l.backupRestore,
              subtitle: lastBackup == null ? l.neverBackedUp : l.lastBackup(Fmt.dateTime(lastBackup)),
              onTap: () => context.push(Routes.backup),
            ),
            _Tile(icon: Icons.import_export_rounded, title: l.importExport, onTap: () => context.push(Routes.importExport)),
          ],
          _Header(l.sectionHelp),
          _Tile(icon: Icons.ondemand_video_rounded, title: l.helpVideos, onTap: () => context.push('${Routes.info}/help')),
          _Tile(icon: Icons.privacy_tip_outlined, title: l.privacyPolicy, onTap: () => context.push('${Routes.info}/privacy')),
          _Tile(icon: Icons.gavel_rounded, title: l.licenseTerms, onTap: () => context.push('${Routes.info}/terms')),
          ListTile(
            key: const Key('about_tile'),
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(l.about),
            subtitle: Text('${l.appTitle} • ${l.version(appVersion)}\n${l.tagline}'),
            isThreeLine: true,
            // Hidden Health Check (spec Section 8 invariants).
            onLongPress: can.settings ? () => context.push(Routes.healthCheck) : null,
          ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}

final _demoProvider = FutureProvider.autoDispose<bool>((ref) => ref.watch(settingsRepoProvider).getBool(SettingKeys.demoData));

final _lastBackupProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  final v = await ref.watch(settingsRepoProvider).get(SettingKeys.lastBackupAt);
  return v == null ? null : DateTime.tryParse(v);
});

String roleLabel(BuildContext context, UserRole? role) {
  final l = context.l10n;
  return switch (role) {
    UserRole.owner => l.roleOwner,
    UserRole.manager => l.roleManager,
    UserRole.cashier => l.roleCashier,
    UserRole.technician => l.roleTechnician,
    null => '-',
  };
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.of(context).primary)),
      );
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.icon, required this.title, required this.onTap, this.subtitle, this.color, this.pro = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;
  final bool pro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final proOn = pro ? (ref.watch(proActiveProvider).value ?? false) : true;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: color == null ? null : TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: !proOn
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(6)),
              child: Text(context.l10n.proBadge,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.light.textPrimary)),
            )
          : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
