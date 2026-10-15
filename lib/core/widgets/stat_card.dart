import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'ltr.dart';

/// Direction of money shown on a stat card. Never rely on colour alone:
/// Lena gets a down-arrow, Dena an up-arrow (spec Section 4).
enum StatTone { neutral, lena, dena, warning }

/// A dashboard card with a label and a big number. Tappable so every number
/// can drill down to the entries behind it (spec Section 1).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.tone = StatTone.neutral,
    this.icon,
    this.badge,
    this.onTap,
  });

  final String label;
  final String value;
  final StatTone tone;
  final IconData? icon;

  /// Optional small badge, e.g. "PRO".
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final theme = Theme.of(context);

    final (Color valueColor, IconData? toneIcon) = switch (tone) {
      StatTone.lena => (c.success, Icons.south_west_rounded),
      StatTone.dena => (c.danger, Icons.north_east_rounded),
      StatTone.warning => (c.warning, Icons.warning_amber_rounded),
      StatTone.neutral => (c.textPrimary, null),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: c.textSecondary),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(color: c.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badge != null) _Badge(text: badge!),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  if (toneIcon != null) ...[
                    Icon(toneIcon, size: 20, color: valueColor),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Ltr(
                        Text(
                          value,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: valueColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              // Dark text reads well on the amber badge in both themes.
              color: AppColors.light.textPrimary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
