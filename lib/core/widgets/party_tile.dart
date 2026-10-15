import 'package:flutter/material.dart';

import '../money/money.dart';
import '../money/money_format.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'ltr.dart';

/// A customer/supplier row in the Khata list.
///
/// [balance] follows the ledger sign convention: positive = the party owes
/// the shop (Lena, green, down-arrow); negative = the shop owes the party
/// (Dena, red, up-arrow). The label text is passed in so it is localized.
class PartyTile extends StatelessWidget {
  const PartyTile({
    super.key,
    required this.name,
    required this.balance,
    required this.lenaLabel,
    required this.denaLabel,
    this.phone,
    this.subtitle,
    this.onTap,
  });

  final String name;
  final String? phone;
  final String? subtitle;
  final Money balance;
  final String lenaLabel;
  final String denaLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final isLena = balance.isPositive;
    final isDena = balance.isNegative;
    final color = isLena ? c.success : (isDena ? c.danger : c.textSecondary);
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: c.primaryContainer,
                child: Text(initial, style: theme.textTheme.titleMedium?.copyWith(color: c.primary)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (phone != null || subtitle != null)
                      Ltr(
                        Text(
                          [phone, subtitle].whereType<String>().join(' • '),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!balance.isZero)
                        Icon(isLena ? Icons.south_west_rounded : Icons.north_east_rounded, size: 16, color: color),
                      Ltr(
                        Text(
                          MoneyFormat.format(balance.abs()),
                          style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (!balance.isZero)
                    Text(isLena ? lenaLabel : denaLabel, style: theme.textTheme.labelMedium?.copyWith(color: color)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
