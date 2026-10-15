import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/stat_card.dart';
import '../data/dashboard_repository.dart';

final dashboardProvider = StreamProvider.autoDispose<DashboardStats>(
    (ref) => DashboardRepository(ref.watch(databaseProvider)).watch(ref.watch(clockProvider)));

final _homeFlagsProvider = FutureProvider.autoDispose<({bool coach, bool backupDue, bool demo})>((ref) async {
  final s = ref.watch(settingsRepoProvider);
  final coachShown = await s.getBool(SettingKeys.coachShown, fallback: true);
  final last = DateTime.tryParse(await s.get(SettingKeys.lastBackupAt) ?? '');
  final demo = await s.getBool(SettingKeys.demoData);
  return (
    coach: !coachShown,
    backupDue: last == null || DateTime.now().difference(last) > const Duration(days: 7),
    demo: demo,
  );
});

/// Route for a recent-activity row, when it has a detail screen.
String? activityRoute(String sourceType, String sourceId) => switch (sourceType) {
      'sale' => Routes.saleDetail(sourceId),
      'purchase' => Routes.purchaseDetail(sourceId),
      _ => null,
    };

/// Home — "Aaj ka Hisaab" (spec 5.2). Every number is tappable.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final can = session.can;
    final stats = ref.watch(dashboardProvider).value;
    final flags = ref.watch(_homeFlagsProvider).value;
    final pro = ref.watch(proActiveProvider).value ?? false;
    String m(Money? x) => Fmt.money(x ?? Money.zero);

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
                          Text(session.business?.name ?? l.homeTitle,
                              style: theme.textTheme.headlineMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${l.homeTitle} • \u2066${Fmt.date(ref.watch(clockProvider)())}\u2069',
                              style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (flags?.demo ?? false)
                            Text(l.demoBadge, style: theme.textTheme.labelSmall?.copyWith(color: c.secondary)),
                        ],
                      ),
                    ),
                    _OfflineBadge(label: l.offlineSafe),
                  ],
                ),
              ),
            ),
            if ((flags?.backupDue ?? false) && can.backup)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    color: c.warning.withValues(alpha: 0.12),
                    child: ListTile(
                      leading: Icon(Icons.backup_outlined, color: c.warning),
                      title: Text(l.backupBanner),
                      subtitle: Text(l.backupReminder),
                      onTap: () => context.push(Routes.backup),
                    ),
                  ),
                ),
              ),
            if (flags?.coach ?? false)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                sliver: SliverToBoxAdapter(child: _CoachMarks(onDone: () async {
                  await ref.read(settingsRepoProvider).set(SettingKeys.coachShown, 'true');
                  ref.invalidate(_homeFlagsProvider);
                })),
              ),
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.md),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.sm + 4,
                  crossAxisSpacing: AppSpacing.sm + 4,
                  // Nastaliq needs taller rows (DECISIONS.md D-007).
                  mainAxisExtent: Directionality.of(context) == TextDirection.rtl ? 128 : 108,
                ),
                delegate: SliverChildListDelegate([
                  StatCard(
                    key: const Key('stat_today_sale'),
                    label: l.todaySale,
                    value: m(stats?.todaySales),
                    icon: Icons.trending_up_rounded,
                    onTap: () => context.push(Routes.salesList),
                  ),
                  StatCard(
                    key: const Key('stat_galla'),
                    label: l.galla,
                    value: m(stats?.galla),
                    icon: Icons.payments_outlined,
                    onTap: can.cashClosing ? () => context.push(Routes.galla) : null,
                  ),
                  StatCard(
                    label: l.lena,
                    value: m(stats?.lena),
                    tone: StatTone.lena,
                    onTap: () => context.go(Routes.khata),
                  ),
                  StatCard(
                    label: l.dena,
                    value: m(stats?.dena),
                    tone: StatTone.dena,
                    onTap: () => context.go(Routes.khata),
                  ),
                  if (can.seeProfit)
                    StatCard(
                      label: '${l.todayProfit} (${l.estimated})',
                      value: m(stats?.todayProfit),
                      icon: Icons.savings_outlined,
                      onTap: can.reports ? () => context.push(Routes.report('pnl')) : null,
                    ),
                  StatCard(
                    label: l.lowStock,
                    value: Fmt.qty(stats?.lowStock ?? 0),
                    tone: (stats?.lowStock ?? 0) > 0 ? StatTone.warning : StatTone.neutral,
                    icon: Icons.inventory_outlined,
                    onTap: () => context.go(Routes.stock),
                  ),
                  StatCard(
                    label: l.qistDueToday,
                    value: Fmt.qty(stats?.qistDue ?? 0),
                    badge: pro ? null : l.proBadge,
                    icon: Icons.event_repeat_rounded,
                    onTap: () => context.push(Routes.qistList),
                  ),
                  StatCard(
                    label: l.repairsReady,
                    value: Fmt.qty(stats?.repairsReady ?? 0),
                    badge: pro ? null : l.proBadge,
                    icon: Icons.build_outlined,
                    onTap: () => context.push(Routes.repairs),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              sliver: SliverToBoxAdapter(child: Text(l.quickActions, style: theme.textTheme.titleLarge)),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.md),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  mainAxisExtent: 124,
                ),
                delegate: SliverChildListDelegate([
                  _QuickAction(icon: Icons.point_of_sale_rounded, label: l.newSale, color: c.primary, onTap: () => context.go(Routes.sale)),
                  if (can.purchase)
                    _QuickAction(icon: Icons.shopping_cart_outlined, label: l.purchase, color: c.primary, onTap: () => context.push(Routes.purchaseNew)),
                  if (can.receivePayment)
                    _QuickAction(
                        icon: Icons.south_west_rounded,
                        label: l.paymentIn,
                        color: c.success,
                        onTap: () => context.push(Routes.paymentNew(incoming: true))),
                  if (can.makePayment)
                    _QuickAction(
                        icon: Icons.north_east_rounded,
                        label: l.paymentOut,
                        color: c.danger,
                        onTap: () => context.push(Routes.paymentNew(incoming: false))),
                  if (can.expenses)
                    _QuickAction(icon: Icons.receipt_long_outlined, label: l.expense, color: c.warning, onTap: () => context.push(Routes.expenseNew)),
                  if (can.cashClosing)
                    _QuickAction(icon: Icons.lock_clock_outlined, label: l.gallaBand, color: c.primary, onTap: () => context.push(Routes.galla)),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              sliver: SliverToBoxAdapter(child: Text(l.recentActivity, style: theme.textTheme.titleLarge)),
            ),
            if (stats == null || stats.recent.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(icon: Icons.history_rounded, title: l.noActivityTitle, message: l.noActivityBody, scrollable: false),
              )
            else
              SliverList.separated(
                itemCount: stats.recent.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: AppSpacing.md),
                itemBuilder: (context, i) {
                  final a = stats.recent[i];
                  final route = activityRoute(a.sourceType, a.sourceId);
                  return ListTile(
                    dense: true,
                    onTap: route == null ? null : () => context.push(route),
                    leading: Icon(_activityIcon(a.sourceType), color: c.primary),
                    title: Text(a.memo.isEmpty ? a.sourceType : a.memo, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${Fmt.time(a.date)} • ${Fmt.date(a.date)}${a.reversal ? ' ${l.srcReversalSuffix}' : ''}'),
                    trailing: Ltr(Text(Fmt.money(a.amount), style: theme.textTheme.titleSmall)),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  static IconData _activityIcon(String t) => switch (t) {
        'sale' => Icons.point_of_sale_rounded,
        'sale_return' || 'purchase_return' => Icons.assignment_return_outlined,
        'purchase' => Icons.shopping_cart_outlined,
        'payment' => Icons.payments_outlined,
        'expense' => Icons.receipt_long_outlined,
        'cash_closing' => Icons.lock_clock_outlined,
        'repair_job' || 'repair_part' => Icons.build_outlined,
        _ => Icons.edit_note_rounded,
      };
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
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(radius: 22, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
              const SizedBox(height: AppSpacing.xs),
              Flexible(
                child: Text(label,
                    style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 3-step coach mark after onboarding (spec 5.1 step 5).
class _CoachMarks extends StatefulWidget {
  const _CoachMarks({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends State<_CoachMarks> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final steps = [
      (Icons.add_circle_rounded, l.coachNewSale),
      (Icons.inventory_2_rounded, l.coachAddStock),
      (Icons.menu_book_rounded, l.coachKhata),
    ];
    return Card(
      color: c.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(children: [
          Icon(steps[_step].$1, color: c.primary, size: 36),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(steps[_step].$2, style: Theme.of(context).textTheme.titleSmall)),
          TextButton(
            key: const Key('coach_next'),
            onPressed: () {
              if (_step < steps.length - 1) {
                setState(() => _step++);
              } else {
                widget.onDone();
              }
            },
            child: Text(_step < steps.length - 1 ? '${l.next} (${_step + 1}/3)' : l.gotIt),
          ),
        ]),
      ),
    );
  }
}
