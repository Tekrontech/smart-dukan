import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/files.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ltr.dart';
import '../../license/presentation/license_screen.dart' show openWhatsApp;
import '../application/statement_pdf.dart';
import '../data/parties_repository.dart';

/// Human label for a ledger row's source document.
String ledgerLabel(BuildContext context, LedgerRow r) {
  final l = context.l10n;
  final base = switch (r.sourceType) {
    'sale' => l.srcSale,
    'sale_return' => l.srcSaleReturn,
    'purchase' => l.srcPurchase,
    'purchase_return' => l.srcPurchaseReturn,
    'payment' => r.debit.isPositive ? l.paymentGiven : l.paymentReceived,
    'party_opening' => l.srcOpening,
    'repair_job' => l.srcRepair,
    'qist_cancel' || 'qist_writeoff' => l.srcQist,
    _ => r.sourceType,
  };
  final memo = r.memo.isEmpty || r.sourceType == 'payment' ? '' : ' • ${r.memo}';
  return '$base$memo${r.reversal ? ' ${l.srcReversalSuffix}' : ''}';
}

/// Party card + ledger (spec 5.6): running balance, date filter, payment
/// in/out, WhatsApp reminder, call and statement PDF.
class PartyDetailScreen extends ConsumerStatefulWidget {
  const PartyDetailScreen({super.key, required this.partyId});

  final String partyId;

  @override
  ConsumerState<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends ConsumerState<PartyDetailScreen> {
  DateTimeRange? _range;

  Future<({Money opening, List<LedgerRow> rows})> _ledger() => ref.read(partiesRepoProvider).ledger(
        widget.partyId,
        from: _range?.start,
        to: _range?.end.add(const Duration(days: 1)),
      );

  Future<void> _statement(Party p) async {
    final l = context.l10n;
    final data = await _ledger();
    if (!mounted) return;
    final business = ref.read(sessionProvider).business!;
    await guard(context, () async {
      final pdf = await buildStatementPdf(
        business: business,
        party: p,
        opening: data.opening,
        rows: data.rows,
        describe: (r) => ledgerLabel(context, r),
        from: _range?.start,
        to: _range?.end.add(const Duration(days: 1)),
      );
      await shareBytes('Statement_${p.name.replaceAll(' ', '_')}.pdf', pdf, mimeType: 'application/pdf');
      return l;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final repo = ref.watch(partiesRepoProvider);
    final can = ref.watch(permissionsProvider);

    return StreamBuilder<Party?>(
      stream: repo.watchParty(widget.partyId),
      builder: (context, ps) {
        final p = ps.data;
        if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return Scaffold(
          appBar: AppBar(
            title: Text(p.name),
            actions: [
              if (can.editParties)
                IconButton(icon: const Icon(Icons.edit_outlined), tooltip: l.edit, onPressed: () => context.push(Routes.partyEdit(p.id))),
            ],
          ),
          body: StreamBuilder<Money>(
            stream: repo.watchBalance(p.id),
            builder: (context, bs) {
              final bal = bs.data ?? Money.zero;
              final lena = bal.isPositive;
              final color = bal.isZero ? c.textSecondary : (lena ? c.success : c.danger);
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (p.phone != null) Ltr(Text(p.phone!, style: theme.textTheme.bodyMedium)),
                        const SizedBox(height: AppSpacing.sm),
                        Row(children: [
                          if (!bal.isZero) Icon(lena ? Icons.south_west_rounded : Icons.north_east_rounded, color: color),
                          const SizedBox(width: AppSpacing.xs),
                          Ltr(Text(Fmt.money(bal.abs()), style: theme.textTheme.displaySmall?.copyWith(color: color))),
                        ]),
                        Text(bal.isZero ? l.settled : (lena ? l.lenaLabel : (p.type == PartyType.customer ? l.advanceLabel : l.denaLabel)),
                            style: theme.textTheme.titleSmall?.copyWith(color: color)),
                        if (p.creditLimit.isPositive) Text('${l.creditLimit}: ${Fmt.money(p.creditLimit)}', style: theme.textTheme.bodySmall),
                      ]),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                    if (can.receivePayment)
                      FilledButton.icon(
                        onPressed: () => context.push(Routes.paymentNew(incoming: true, partyId: p.id)),
                        icon: const Icon(Icons.south_west_rounded),
                        label: Text(l.paymentReceived),
                      ),
                    if (can.makePayment)
                      FilledButton.tonalIcon(
                        onPressed: () => context.push(Routes.paymentNew(incoming: false, partyId: p.id)),
                        icon: const Icon(Icons.north_east_rounded),
                        label: Text(l.paymentGiven),
                      ),
                    if (bal.isPositive)
                      OutlinedButton.icon(
                        onPressed: () => openWhatsApp(
                          l.reminderTemplate(p.name, ref.read(sessionProvider).business!.name,
                              MoneyFormat.format(bal, symbol: false, urduDigits: false)),
                          phone: p.phone,
                        ),
                        icon: const Icon(Icons.chat_rounded),
                        label: Text(l.sendReminder),
                      ),
                    if (p.phone != null)
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri(scheme: 'tel', path: p.phone)),
                        icon: const Icon(Icons.call_rounded),
                        label: Text(l.call),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _statement(p),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(l.shareStatement),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  Row(children: [
                    Expanded(child: Text(l.ledger, style: theme.textTheme.titleMedium)),
                    TextButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final r = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(now.year + 1),
                          initialDateRange: _range,
                        );
                        setState(() => _range = r);
                      },
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text(_range == null ? l.all : '${Fmt.date(_range!.start)} – ${Fmt.date(_range!.end)}'),
                    ),
                    if (_range != null) IconButton(onPressed: () => setState(() => _range = null), icon: const Icon(Icons.close)),
                  ]),
                  // Rebuilds with the balance stream so new entries show up.
                  FutureBuilder<({Money opening, List<LedgerRow> rows})>(
                    key: ValueKey('${bal.paisa}:${_range?.start}:${_range?.end}'),
                    future: _ledger(),
                    builder: (context, snap) {
                      final data = snap.data;
                      if (data == null) return const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator()));
                      return Column(children: [
                        _LedgerHeader(),
                        if (_range != null)
                          _LedgerLine(date: '', label: l.openingRow, debit: Money.zero, credit: Money.zero, running: data.opening),
                        if (data.rows.isEmpty) Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text(l.noLedger)),
                        for (final r in data.rows.reversed)
                          InkWell(
                            onTap: () {
                              if (r.sourceType == 'sale') context.push(Routes.saleDetail(r.sourceId));
                              if (r.sourceType == 'purchase') context.push(Routes.purchaseDetail(r.sourceId));
                            },
                            child: _LedgerLine(
                              date: Fmt.date(r.date),
                              label: ledgerLabel(context, r),
                              debit: r.debit,
                              credit: r.credit,
                              running: r.running,
                            ),
                          ),
                      ]);
                    },
                  ),
                  const SizedBox(height: 96),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _LedgerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(children: [
        Expanded(flex: 4, child: Text(l.details, style: s)),
        Expanded(flex: 2, child: Text(l.debit, style: s, textAlign: TextAlign.end)),
        Expanded(flex: 2, child: Text(l.credit, style: s, textAlign: TextAlign.end)),
        Expanded(flex: 3, child: Text(l.runningBalance, style: s, textAlign: TextAlign.end)),
      ]),
    );
  }
}

class _LedgerLine extends StatelessWidget {
  const _LedgerLine({required this.date, required this.label, required this.debit, required this.credit, required this.running});

  final String date;
  final String label;
  final Money debit;
  final Money credit;
  final Money running;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    String m(Money x) => x.isZero ? '' : Fmt.moneyPlain(x);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.outline))),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (date.isNotEmpty) Text(date, style: t.bodySmall),
          ]),
        ),
        Expanded(flex: 2, child: Ltr(Text(m(debit), textAlign: TextAlign.end, style: t.bodyMedium?.copyWith(color: c.success)))),
        Expanded(flex: 2, child: Ltr(Text(m(credit), textAlign: TextAlign.end, style: t.bodyMedium?.copyWith(color: c.danger)))),
        Expanded(flex: 3, child: Ltr(Text(Fmt.moneyPlain(running), textAlign: TextAlign.end, style: t.titleSmall))),
      ]),
    );
  }
}
