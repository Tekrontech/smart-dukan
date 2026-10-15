import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/pin_gate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/sales_repository.dart';
import 'receipt_actions.dart';

String docStatusLabel(BuildContext context, DocStatus s) => switch (s) {
      DocStatus.posted => context.l10n.statusPosted,
      DocStatus.reversed => context.l10n.statusReversed,
      DocStatus.reversal => context.l10n.statusReversal,
    };

/// Sale detail: items, totals, returns; share, print, return, reverse.
class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    return StreamBuilder<SaleView?>(
      stream: ref.watch(salesRepoProvider).watch(saleId),
      builder: (context, snap) {
        final v = snap.data;
        if (v == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final s = v.sale;
        final posted = s.status == DocStatus.posted;
        return Scaffold(
          appBar: AppBar(
            title: Ltr(Text(s.invoiceNo)),
            actions: [
              IconButton(tooltip: l.share, icon: const Icon(Icons.share_rounded), onPressed: () => shareReceipt(context, ref, s.id, s.invoiceNo)),
              IconButton(tooltip: l.print, icon: const Icon(Icons.print_rounded), onPressed: () => printReceipt(context, ref, s.id)),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'image') shareReceiptImage(context, ref, s.id, s.invoiceNo);
                },
                itemBuilder: (_) => [PopupMenuItem(value: 'image', child: Text(l.shareImage))],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Card(
                child: ListTile(
                  title: Text(v.party?.name ?? l.walkInCustomer),
                  subtitle: Text(Fmt.dateTime(s.date)),
                  trailing: Chip(label: Text(docStatusLabel(context, s.status))),
                  onTap: v.party == null ? null : () => context.push(Routes.party(v.party!.id)),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final i in v.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(i.description),
                  subtitle: Ltr(Text('${i.unitQty} × ${Fmt.money(i.unitPrice)}'
                      '${i.discount.isZero ? '' : '  − ${Fmt.money(i.discount)}'}'
                      '${v.returnedQty(i.id) > 0 ? '  ↩ ${v.returnedQty(i.id)}' : ''}')),
                  trailing: Ltr(Text(Fmt.money(i.lineTotal), style: theme.textTheme.titleSmall)),
                ),
              const Divider(),
              _row(context, l.subtotal, s.subtotal),
              if (!s.discount.isZero) _row(context, l.discount, -s.discount),
              if (!s.tax.isZero) _row(context, l.tax, s.tax),
              if (!s.delivery.isZero) _row(context, l.delivery, s.delivery),
              if (!s.markup.isZero) _row(context, l.markup, s.markup),
              _row(context, l.total, s.total, big: true),
              _row(context, l.paid, s.paid),
              if (!s.due.isZero) _row(context, l.due, s.due, color: c.danger),
              if (v.returns.isNotEmpty) ...[
                const Divider(),
                Text(l.returnsOnInvoice, style: theme.textTheme.titleSmall),
                for (final r in v.returns)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Ltr(Text(r.returnNo)),
                    subtitle: Text('${Fmt.dateTime(r.date)} • ${docStatusLabel(context, r.status)}'),
                    trailing: Ltr(Text('− ${Fmt.money(r.amount)}')),
                  ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (posted && s.paymentMode != SalePaymentMode.qist)
                PrimaryButton(
                  label: l.returnItems,
                  icon: Icons.assignment_return_outlined,
                  outlined: true,
                  onPressed: () => context.push(Routes.saleReturn(s.id)),
                ),
              if (posted && s.paymentMode == SalePaymentMode.qist)
                PrimaryButton(
                  label: l.qistPlans,
                  icon: Icons.event_repeat_rounded,
                  outlined: true,
                  onPressed: () async {
                    final db = ref.read(databaseProvider);
                    final plan = await (db.select(db.qistPlans)..where((q) => q.saleId.equals(s.id))).getSingleOrNull();
                    if (plan != null && context.mounted) context.push(Routes.qist(plan.id));
                  },
                ),
              if (posted) ...[
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: l.reverseSale,
                  icon: Icons.undo_rounded,
                  outlined: true,
                  onPressed: () async {
                    final ok = await ConfirmSheet.show(context,
                        title: l.reverseConfirmTitle,
                        message: l.reverseConfirmBody,
                        confirmLabel: l.reverse,
                        cancelLabel: l.cancel,
                        destructive: true);
                    if (!ok || !context.mounted) return;
                    if (!await ref.read(pinGateProvider).requireOwner(context)) return;
                    if (!context.mounted) return;
                    final r = await guard(context, () => ref.read(saleServiceProvider).reverseSale(s.id));
                    if (r != null && context.mounted) showMessage(context, l.reversed);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, String label, Money value, {bool big = false, Color? color}) {
    final style = (big ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.bodyLarge)?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(label, style: style)), Ltr(Text(Fmt.money(value), style: style))]),
    );
  }
}
