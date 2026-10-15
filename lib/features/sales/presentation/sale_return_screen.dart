import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/labels.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/sale_service.dart';
import '../data/sales_repository.dart';

/// Sale return (spec 8.1): choose quantities; the value first reduces what
/// the customer owes on the invoice, the rest is refunded or kept as credit.
class SaleReturnScreen extends ConsumerStatefulWidget {
  const SaleReturnScreen({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<SaleReturnScreen> createState() => _SaleReturnScreenState();
}

class _SaleReturnScreenState extends ConsumerState<SaleReturnScreen> {
  SaleView? _v;
  final Map<String, int> _qty = {};
  bool _refund = true;
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(salesRepoProvider).load(widget.saleId).then((v) {
      if (mounted) setState(() => _v = v);
    });
  }

  Money _estimate(SaleView v) {
    var total = Money.zero;
    for (final i in v.items) {
      final q = _qty[i.id] ?? 0;
      if (q > 0) total += (i.netAmount + i.taxAmount).ratio(q, i.qty);
    }
    return total;
  }

  Future<void> _save() async {
    final v = _v!;
    final lines = [for (final e in _qty.entries) if (e.value > 0) SaleReturnLine(saleItemId: e.key, qty: e.value)];
    if (lines.isEmpty) return;
    setState(() => _busy = true);
    final ok = await guard(context, () => ref.read(saleServiceProvider).returnSale(
          saleId: v.sale.id,
          lines: lines,
          refundRemainder: _refund,
          refundMethod: _method,
        ));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok != null) {
      savedHaptic();
      showMessage(context, context.l10n.returnSaved);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final v = _v;
    if (v == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(l.returnItems)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Ltr(Text(v.sale.invoiceNo, style: Theme.of(context).textTheme.titleMedium)),
          for (final i in v.items)
            Builder(builder: (context) {
              final returned = v.returnedQty(i.id);
              final max = i.qty - returned;
              final q = _qty[i.id] ?? 0;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(i.description),
                subtitle: Text(l.soldQty(Fmt.qty(i.qty), Fmt.qty(returned))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    onPressed: q > 0 ? () => setState(() => _qty[i.id] = q - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Ltr(Text('$q', style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    key: Key('ret_plus_${i.id}'),
                    onPressed: q < max ? () => setState(() => _qty[i.id] = q + 1) : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ]),
              );
            }),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.returnValue),
            trailing: Ltr(Text(Fmt.money(_estimate(v)), style: Theme.of(context).textTheme.titleLarge)),
          ),
          if (v.sale.partyId != null) ...[
            RadioGroup<bool>(
              groupValue: _refund,
              onChanged: (x) => setState(() => _refund = x ?? true),
              child: Column(children: [
                RadioListTile<bool>(value: true, title: Text(l.refundNow)),
                RadioListTile<bool>(value: false, title: Text(l.keepCredit)),
              ]),
            ),
          ],
          if (_refund)
            Wrap(spacing: AppSpacing.sm, children: [
              for (final m in PaymentMethod.values)
                ChoiceChip(label: Text(context.methodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
            ]),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: l.save,
            icon: Icons.check_rounded,
            loading: _busy,
            onPressed: _qty.values.any((q) => q > 0) ? _save : null,
          ),
        ],
      ),
    );
  }
}
