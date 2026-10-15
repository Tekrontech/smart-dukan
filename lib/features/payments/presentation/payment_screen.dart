import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/amount_keypad.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/labels.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/primary_button.dart';
import '../../parties/presentation/party_picker.dart';

class _OpenDoc {
  _OpenDoc(this.id, this.no, this.date, this.open);

  final String id;
  final String no;
  final DateTime date;
  final Money open;
  Money applied = Money.zero;
}

/// Payment In / Out (spec 5.7): party, amount, method, note, allocation to
/// open invoices — oldest first by default, editable.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, required this.incoming, this.partyId});

  final bool incoming;
  final String? partyId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String? _partyId;
  String? _partyName;
  Money _balance = Money.zero;
  Money _amount = Money.zero;
  PaymentMethod _method = PaymentMethod.cash;
  final _ref = TextEditingController();
  final _note = TextEditingController();
  List<_OpenDoc> _docs = [];
  bool _manual = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.partyId != null) _setParty(widget.partyId!, null);
  }

  @override
  void dispose() {
    _ref.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _setParty(String id, String? name) async {
    final p = await ref.read(partiesRepoProvider).party(id);
    final q = ref.read(ledgerProvider);
    final bal = await q.partyBalance(id);
    final docs = widget.incoming
        ? [for (final s in await q.openSales(id)) _OpenDoc(s.sale.id, s.sale.invoiceNo, s.sale.date, s.open)]
        : [for (final x in await q.openPurchases(id)) _OpenDoc(x.purchase.id, x.purchase.billNo, x.purchase.date, x.open)];
    if (!mounted) return;
    setState(() {
      _partyId = id;
      _partyName = name ?? p?.name;
      _balance = bal;
      _docs = docs;
      _autoApply();
    });
  }

  void _autoApply() {
    var left = _amount;
    for (final d in _docs) {
      d.applied = Money.min(left, d.open);
      left -= d.applied;
    }
  }

  Money get _allocated => Money.sum(_docs.map((d) => d.applied));

  Future<void> _save() async {
    if (_partyId == null || !_amount.isPositive) return;
    setState(() => _busy = true);
    final svc = ref.read(paymentServiceProvider);
    final alloc = _manual ? {for (final d in _docs) if (d.applied.isPositive) d.id: d.applied} : null;
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final reference = _ref.text.trim().isEmpty ? null : _ref.text.trim();
    final ok = await guard(
      context,
      () => widget.incoming
          ? svc.receive(partyId: _partyId!, amount: _amount, method: _method, allocations: alloc, note: note, reference: reference)
          : svc.pay(partyId: _partyId!, amount: _amount, method: _method, allocations: alloc, note: note, reference: reference),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok != null) {
      savedHaptic();
      showMessage(context, context.l10n.paymentSaved);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final tone = widget.incoming ? c.success : c.danger;
    return Scaffold(
      appBar: AppBar(title: Text(widget.incoming ? l.paymentInTitle : l.paymentOutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: ListTile(
              key: const Key('payment_party'),
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(_partyName ?? l.chooseParty),
              subtitle: _partyId == null ? Text(l.party) : Ltr(Text(l.currentBalance(Fmt.money(_balance)))),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final p = await pickParty(context, kind: widget.incoming ? PartyType.customer : PartyType.supplier, allowWalkIn: false);
                if (p?.id != null) _setParty(p!.id!, p.name);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            key: const Key('payment_amount'),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            onTap: () async {
              final m = await AmountKeypad.show(context, title: l.amount, doneLabel: l.done, initial: _amount);
              if (m != null) {
                setState(() {
                  _amount = m;
                  if (!_manual) _autoApply();
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(AppSpacing.cardRadius)),
              child: Column(children: [
                Icon(widget.incoming ? Icons.south_west_rounded : Icons.north_east_rounded, color: tone),
                Text(l.amount, style: theme.textTheme.labelLarge),
                Ltr(Text(Fmt.money(_amount), style: theme.textTheme.displayMedium?.copyWith(color: tone))),
              ]),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(l.paymentMethod, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, children: [
            for (final m in PaymentMethod.values)
              ChoiceChip(label: Text(context.methodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
          ]),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _ref, decoration: InputDecoration(labelText: '${l.reference} (${l.optional})')),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _note, decoration: InputDecoration(labelText: l.note)),
          if (_docs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(l.allocation, style: theme.textTheme.titleSmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.autoOldestFirst),
              value: !_manual,
              onChanged: (v) => setState(() {
                _manual = !v;
                if (!_manual) _autoApply();
              }),
            ),
            for (final d in _docs)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: d.applied.isPositive,
                onChanged: !_manual
                    ? null
                    : (v) => setState(() {
                          if (v == true) {
                            final left = _amount - _allocated;
                            d.applied = Money.min(d.open, Money.max(left, Money.zero));
                          } else {
                            d.applied = Money.zero;
                          }
                        }),
                title: Ltr(Text('${d.no} • ${Fmt.date(d.date)}')),
                subtitle: Text(l.openDue(Fmt.money(d.open))),
                secondary: Ltr(Text(Fmt.money(d.applied))),
              ),
            if (_amount > _allocated)
              Text(l.unallocated(Fmt.money(_amount - _allocated)), style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            key: const Key('payment_save'),
            label: l.save,
            icon: Icons.check_rounded,
            loading: _busy,
            onPressed: _partyId != null && _amount.isPositive ? _save : null,
          ),
        ],
      ),
    );
  }
}
