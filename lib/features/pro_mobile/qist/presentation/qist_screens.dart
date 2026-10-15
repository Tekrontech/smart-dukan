import 'package:drift/drift.dart' show OrderingTerm, TableInfoUtils;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../app/router.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/security/pin_gate.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/fmt.dart';
import '../../../../core/widgets/amount_keypad.dart';
import '../../../../core/widgets/confirm_sheet.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/ltr.dart';
import '../../../../core/widgets/primary_button.dart';

String planStatusLabel(BuildContext context, QistPlanStatus s) => switch (s) {
      QistPlanStatus.active => context.l10n.planActive,
      QistPlanStatus.completed => context.l10n.planCompleted,
      QistPlanStatus.cancelled => context.l10n.planCancelled,
    };

bool _overdue(QistScheduleRow r, DateTime today) => r.status != QistRowStatus.paid && r.dueDate.isBefore(today);

class _PlanRow {
  const _PlanRow(this.plan, this.party, this.nextDue, this.overdue);

  final QistPlan plan;
  final String party;
  final DateTime? nextDue;
  final bool overdue;
}

final _plansProvider = StreamProvider.autoDispose<List<_PlanRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        'SELECT q.*, p.name pn, (SELECT MIN(s.due_date) FROM qist_schedule s WHERE s.plan_id = q.id AND s.status != \'paid\') nd '
        'FROM qist_plans q JOIN parties p ON p.id = q.party_id ORDER BY q.status, nd',
        readsFrom: {db.qistPlans, db.qistSchedule, db.parties},
      )
      .watch()
      .asyncMap((rows) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <_PlanRow>[];
    for (final r in rows) {
      final plan = await db.qistPlans.mapFromRow(r);
      final nd = r.readNullable<DateTime>('nd');
      out.add(_PlanRow(plan, r.read<String>('pn'), nd, plan.status == QistPlanStatus.active && nd != null && nd.isBefore(today)));
    }
    return out;
  });
});

/// Qist plans with an overdue filter (spec 5.9).
class QistListScreen extends ConsumerStatefulWidget {
  const QistListScreen({super.key});

  @override
  ConsumerState<QistListScreen> createState() => _QistListScreenState();
}

class _QistListScreenState extends ConsumerState<QistListScreen> {
  bool _overdueOnly = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final rows = (ref.watch(_plansProvider).value ?? const <_PlanRow>[]).where((r) => !_overdueOnly || r.overdue).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.qistPlans),
        actions: [
          FilterChip(label: Text(l.overdueOnly), selected: _overdueOnly, onSelected: (v) => setState(() => _overdueOnly = v)),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: rows.isEmpty
          ? EmptyState(icon: Icons.event_repeat_rounded, title: l.noQist, message: '')
          : ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = rows[i];
                return ListTile(
                  onTap: () => context.push(Routes.qist(r.plan.id)),
                  leading: Icon(Icons.event_repeat_rounded, color: r.overdue ? c.danger : c.primary),
                  title: Text(r.party),
                  subtitle: Text([
                    planStatusLabel(context, r.plan.status),
                    if (r.nextDue != null) Fmt.date(r.nextDue!),
                    if (r.overdue) l.rowOverdue,
                  ].join(' • ')),
                  trailing: Ltr(Text(Fmt.money(r.plan.total))),
                );
              },
            ),
    );
  }
}

class QistDetailScreen extends ConsumerWidget {
  const QistDetailScreen({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final db = ref.watch(databaseProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return StreamBuilder<QistPlan?>(
      stream: (db.select(db.qistPlans)..where((q) => q.id.equals(planId))).watchSingleOrNull(),
      builder: (context, ps) {
        final plan = ps.data;
        if (plan == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return StreamBuilder<List<QistScheduleRow>>(
          stream: (db.select(db.qistSchedule)..where((s) => s.planId.equals(planId))..orderBy([(s) => OrderingTerm.asc(s.seq)])).watch(),
          builder: (context, ss) {
            final rows = ss.data ?? const <QistScheduleRow>[];
            final collected = plan.downPayment + Money.sum(rows.map((r) => r.amountPaid));
            final outstanding = plan.total - collected;
            final active = plan.status == QistPlanStatus.active;
            final svc = ref.read(qistServiceProvider);
            return Scaffold(
              appBar: AppBar(title: Text(l.qistPlans)),
              body: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(planStatusLabel(context, plan.status), style: theme.textTheme.titleMedium)),
                          TextButton(onPressed: () => context.push(Routes.saleDetail(plan.saleId)), child: Text(l.invoice)),
                        ]),
                        _kv(context, l.price, plan.cashPrice),
                        _kv(context, l.markup, plan.markup),
                        _kv(context, l.qistTotal, plan.total, bold: true),
                        _kv(context, l.downPayment, plan.downPayment),
                        _kv(context, l.collected, collected, color: c.success),
                        _kv(context, l.outstanding, outstanding, color: c.danger, bold: true),
                        if (plan.guarantorName != null)
                          Text('${l.guarantor}: ${plan.guarantorName}${plan.guarantorPhone == null ? '' : ' • ${plan.guarantorPhone}'}'),
                      ]),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(l.qistSchedule, style: theme.textTheme.titleSmall),
                  for (final r in rows)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(radius: 14, child: Text('${r.seq}')),
                      title: Ltr(Text(Fmt.date(r.dueDate))),
                      subtitle: Text(_overdue(r, today) && active
                          ? l.rowOverdue
                          : switch (r.status) {
                              QistRowStatus.due => l.rowDue,
                              QistRowStatus.partial => l.rowPartial,
                              QistRowStatus.paid => l.rowPaid,
                            }),
                      trailing: Ltr(Text('${Fmt.moneyPlain(r.amountPaid)} / ${Fmt.money(r.amountDue)}',
                          style: TextStyle(color: _overdue(r, today) && active ? c.danger : null))),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  if (active) ...[
                    PrimaryButton(
                      key: const Key('qist_collect'),
                      label: l.collectInstalment,
                      icon: Icons.south_west_rounded,
                      onPressed: () async {
                        final next = rows.where((r) => r.status != QistRowStatus.paid).firstOrNull;
                        final a = await AmountKeypad.show(context,
                            title: l.collectInstalment, doneLabel: l.done, initial: next == null ? null : next.amountDue - next.amountPaid);
                        if (a == null || !context.mounted) return;
                        final ok = await guard(context, () => svc.collect(planId, a));
                        if (ok != null && context.mounted) {
                          savedHaptic();
                          showMessage(context, l.qistCollected);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PrimaryButton(
                      label: l.cancelTakeBack,
                      icon: Icons.assignment_return_outlined,
                      outlined: true,
                      onPressed: () async {
                        if (!await ref.read(pinGateProvider).requireOwner(context) || !context.mounted) return;
                        final v = await AmountKeypad.show(context, title: l.recoveryValue, doneLabel: l.done);
                        if (v == null || !context.mounted) return;
                        await guard(context, () => svc.cancelWithRecovery(planId, recoveryValue: v));
                      },
                    ),
                  ],
                  if (plan.status != QistPlanStatus.completed && outstanding.isPositive) ...[
                    const SizedBox(height: AppSpacing.sm),
                    PrimaryButton(
                      label: l.writeOff,
                      icon: Icons.money_off_rounded,
                      outlined: true,
                      onPressed: () async {
                        final ok = await ConfirmSheet.show(context,
                            title: l.writeOff, message: l.writeOffConfirm, confirmLabel: l.writeOff, cancelLabel: l.cancel, destructive: true);
                        if (!ok || !context.mounted) return;
                        if (!await ref.read(pinGateProvider).requireOwner(context) || !context.mounted) return;
                        await guard(context, () => svc.writeOff(planId));
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _kv(BuildContext context, String k, Money v, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k)),
          Ltr(Text(Fmt.money(v), style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : null))),
        ]),
      );
}
