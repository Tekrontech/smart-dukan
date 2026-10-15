import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/accounting/health_check.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Privacy policy, licence terms and help (spec 9 Legal and store).
class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key, required this.page});

  final String page;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (title, body) = switch (page) {
      'privacy' => (l.privacyPolicy, l.privacyBody),
      'terms' => (l.licenseTerms, l.termsBody),
      _ => (l.helpVideos, l.helpVideosBody),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [Text(body, style: Theme.of(context).textTheme.bodyLarge)],
      ),
    );
  }
}

final _healthProvider = FutureProvider.autoDispose<List<HealthIssue>>((ref) => HealthCheck(ref.watch(databaseProvider)).run());

/// Hidden Health Check: runs every Section 8 invariant on this phone.
class HealthCheckScreen extends ConsumerWidget {
  const HealthCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final result = ref.watch(_healthProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.healthCheck),
        actions: [IconButton(tooltip: l.runAgain, onPressed: () => ref.invalidate(_healthProvider), icon: const Icon(Icons.refresh))],
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errGeneric)),
        data: (issues) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Icon(issues.isEmpty ? Icons.verified_rounded : Icons.error_outline_rounded,
                size: 64, color: issues.isEmpty ? c.success : c.danger),
            const SizedBox(height: AppSpacing.sm),
            Text(issues.isEmpty ? l.healthOk : l.healthIssues(issues.length),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            for (final i in issues)
              Card(
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded, color: c.danger),
                  title: Text(i.check),
                  subtitle: Text(i.detail),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
