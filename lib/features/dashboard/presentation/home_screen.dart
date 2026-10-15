import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/coming_soon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/stat_card.dart';

/// Home — "Aaj ka Hisaab" (spec Section 5.2).
///
/// Milestone 1: layout only, all figures are zero. Live figures come from
/// the posting engine in Milestone 7.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final zero = Money.zero.formatted;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.homeTitle, style: theme.textTheme.headlineMedium),
                          const SizedBox(height: 2),
                          Ltr(Text(_today(), style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ),
                    _OfflineBadge(label: l.offlineSafe),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.md),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.sm + 4,
                crossAxisSpacing: AppSpacing.sm + 4,
                childAspectRatio: 1.35,
                children: [
                  StatCard(label: l.todaySale, value: zero, icon: Icons.trending_up_rounded, onTap: () => showComingSoon(context)),
                  StatCard(label: l.galla, value: zero, icon: Icons.payments_outlined, onTap: () => showComingSoon(context)),
                  StatCard(label: l.lena, value: zero, tone: StatTone.lena, onTap: () => showComingSoon(context)),
                  StatCard(label: l.dena, value: zero, tone: StatTone.dena, onTap: () => showComingSoon(context)),
                  StatCard(label: l.todayProfit, value: zero, icon: Icons.savings_outlined, onTap: () => showComingSoon(context)),
                  StatCard(label: l.lowStock, value: '0', icon: Icons.inventory_outlined, onTap: () => showComingSoon(context)),
                  StatCard(label: l.qistDueToday, value: '0', badge: l.proBadge, icon: Icons.event_repeat_rounded, onTap: () => showComingSoon(context)),
                  StatCard(label: l.repairsReady, value: '0', badge: l.proBadge, icon: Icons.build_outlined, onTap: () => showComingSoon(context)),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              sliver: SliverToBoxAdapter(child: Text(l.quickActions, style: theme.textTheme.titleLarge)),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.md),
              sliver: SliverGrid.count(
                crossAxisCount: 3,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 0.8,
                children: [
                  _QuickAction(icon: Icons.point_of_sale_rounded, label: l.newSale, color: c.primary),
                  _QuickAction(icon: Icons.shopping_cart_outlined, label: l.purchase, color: c.primary),
                  _QuickAction(icon: Icons.south_west_rounded, label: l.paymentIn, color: c.success),
                  _QuickAction(icon: Icons.north_east_rounded, label: l.paymentOut, color: c.danger),
                  _QuickAction(icon: Icons.receipt_long_outlined, label: l.expense, color: c.warning),
                  _QuickAction(icon: Icons.lock_clock_outlined, label: l.gallaBand, color: c.primary),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              sliver: SliverToBoxAdapter(child: Text(l.recentActivity, style: theme.textTheme.titleLarge)),
            ),
            SliverToBoxAdapter(
              child: EmptyState(icon: Icons.history_rounded, title: l.noActivityTitle, message: l.noActivityBody, scrollable: false),
            ),
            // Room so the floating "+ Nayi Sale" button never covers content.
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
      ),
    );
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 16, color: c.primary),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.primary)),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showComingSoon(context),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
