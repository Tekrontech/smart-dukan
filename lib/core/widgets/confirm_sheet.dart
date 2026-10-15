import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'primary_button.dart';

/// Confirmation bottom sheet used for every destructive action
/// (spec Section 4). Returns `true` only when the user confirms.
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.destructive = false,
    this.icon,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData? icon;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
    IconData? icon,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ConfirmSheet(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        icon: icon,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final accent = destructive ? c.danger : c.primary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? (destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded), size: 48, color: accent),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            Theme(
              data: theme.copyWith(colorScheme: theme.colorScheme.copyWith(primary: accent)),
              child: PrimaryButton(
                label: confirmLabel,
                icon: destructive ? Icons.delete_outline_rounded : Icons.check_rounded,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(label: cancelLabel, outlined: true, onPressed: () => Navigator.of(context).pop(false)),
          ],
        ),
      ),
    );
  }
}
