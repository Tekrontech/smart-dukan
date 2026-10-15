import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'primary_button.dart';

/// Returns true when Mobile Shop Pro is active; otherwise explains and
/// offers the licence screen. Existing Pro records stay readable — only
/// creating new Pro records is gated (spec Section 2 rules).
Future<bool> requirePro(BuildContext context, WidgetRef ref) async {
  if (await ref.read(proActiveProvider.future)) return true;
  if (!context.mounted) return false;
  final l = context.l10n;
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded, size: 48, color: AppColors.of(ctx).secondary),
            const SizedBox(height: AppSpacing.sm),
            Text(l.proRequired, style: Theme.of(ctx).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(l.proFeatures, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: l.getPro,
              icon: Icons.lock_open_rounded,
              onPressed: () {
                Navigator.of(ctx).pop();
                context.push(Routes.license);
              },
            ),
          ],
        ),
      ),
    ),
  );
  return false;
}
