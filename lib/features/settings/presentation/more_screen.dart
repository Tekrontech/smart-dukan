import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_spacing.dart';

/// More / Settings. Milestone 1 has language and theme; the rest of
/// spec Section 5.11 is added in Milestones 3 and 9.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static const String appVersion = '0.1.0';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final prefs = ref.watch(appPreferencesProvider);
    final notifier = ref.read(appPreferencesProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(l.language, style: theme.textTheme.titleMedium),
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
          const SizedBox(height: AppSpacing.lg),
          Text(l.theme, style: theme.textTheme.titleMedium),
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
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(l.about),
            subtitle: Text('${l.appTitle} • ${l.version(appVersion)}\n${l.tagline}'),
            isThreeLine: true,
          ),
          const SizedBox(height: 88),
        ],
      ),
    );
  }
}
