import 'package:drift/drift.dart' show OrderingTerm, BooleanExpressionOperators;
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
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/labels.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/primary_button.dart';
import '../../sales/presentation/sale_detail_screen.dart' show docStatusLabel;
import '../application/purchase_service.dart';

class _PurchaseView {
  const _PurchaseView(this.purchase, this.items, this.party, this.returned, this.units);

  final Purchase purchase;
  final List<PurchaseItem> items;
  final Party? party;
  final Map<String, ({int qty, Money amount})> returned;
  final List<ImeiUnit> units;
}

final _purchaseProvider = StreamProvider.autoDispose.family<_PurchaseView?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.purchases)..where((p) => p.id.equals(id))).watchSingleOrNull().asyncMap((p) async {
    if (p == null) return null;
    final items = await (db.select(db.purchaseItems)..where((i) => i.purchaseId.equals(id))).get();
    final party = p.partyId == null ? null : await (db.select(db.parties)..where((x) => x.id.equals(p.partyId!))).getSingleOrNull();
    final returned = await ref.read(purchaseServiceProvider).returnedSoFar(id);
    final units = await (db.select(db.imeiUnits)..where((u) => u.purchaseRefId.equals(id))).get();
    return _PurchaseView(p, items, party, returned, units);
  });
});

class PurchaseDetailScreen extends ConsumerWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final v = ref.watch(_purchaseProvider(purchaseId)).value;
    if (v == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final p = v.purchase;
    final posted = p.status == DocStatus.posted;
    Widget row(String k, Money m, {Color? color, bool big = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: big ? Theme.of(context).textTheme.titleLarge : null)),
            Ltr(Text(Fmt.money(m), style: (big ? Theme.of(context).textTheme.titleLarge : null)?.copyWith(color: color) ?? TextStyle(color: color))),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Ltr(Text(p.billNo))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: ListTile(
              title: Text(v.party?.name ?? l.noSupplier),
              subtitle: Text('${Fmt.dateTime(p.date)}${p.supplierBillNo == null ? '' : ' • ${p.supplierBillNo}'}'),
              trailing: Chip(label: Text(docStatusLabel(context, p.status))),
              onTap: v.party == null ? null : () => context.push(Routes.party(v.party!.id)),
            ),
          ),
          for (final i in v.items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(i.description),
              subtitle: Ltr(Text('${i.unitQty} × ${Fmt.money(i.unitCost)}'
                  '${(v.returned[i.id]?.qty ?? 0) > 0 ? '  ↩ ${v.returned[i.id]!.qty}' : ''}')),
              trailing: Ltr(Text(Fmt.money(i.lineTotal))),
            ),
          const Divider(),
          row(l.subtotal, p.subtotal),
          if (!p.discount.isZero) row(l.discount, -p.discount),
          if (!p.extraCost.isZero) row(l.extraCost, p.extraCost),
          row(l.total, p.total, big: true),
          row('${l.paid} (${context.methodLabel(p.paidMethod)})', p.paid),
          if (!p.due.isZero) row(l.due, p.due, color: c.danger),
          if (p.billPhotoPath != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.image_outlined),
              title: Text(l.billPhoto),
              onTap: () => _showPhoto(context, ref, p.billPhotoPath!),
            ),
          const SizedBox(height: AppSpacing.lg),
          if (posted && ref.watch(permissionsProvider).purchase) ...[
            PrimaryButton(
              label: l.returnItems,
              icon: Icons.assignment_return_outlined,
              outlined: true,
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _ReturnSheet(view: v),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: l.reversePurchase,
              icon: Icons.undo_rounded,
              outlined: true,
              onPressed: () async {
                final ok = await ConfirmSheet.show(context,
                    title: l.reverseConfirmTitle, message: l.reverseConfirmBody, confirmLabel: l.reverse, cancelLabel: l.cancel, destructive: true);
                if (!ok || !context.mounted) return;
                if (!await ref.read(pinGateProvider).requireOwner(context) || !context.mounted) return;
                final r = await guard(context, () => ref.read(purchaseServiceProvider).reversePurchase(p.id));
                if (r != null && context.mounted) showMessage(context, l.reversed);
              },
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showPhoto(BuildContext context, WidgetRef ref, String name) async {
  final bytes = await ref.read(photoVaultProvider).read(name);
  if (bytes == null || !context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(bytes))));
}

class _ReturnSheet extends ConsumerStatefulWidget {
  const _ReturnSheet({required this.view});

  final _PurchaseView view;

  @override
  ConsumerState<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends ConsumerState<_ReturnSheet> {
  final Map<String, int> _qty = {};
  final Set<String> _imeis = {};
  bool _refund = true;
  bool _busy = false;

  Future<void> _save() async {
    final v = widget.view;
    final lines = <PurchaseReturnLine>[];
    for (final i in v.items) {
      final units = v.units.where((u) => u.productId == i.productId && _imeis.contains(u.id)).map((u) => u.id).toList();
      if ((_qty[i.id] ?? 0) > 0 || units.isNotEmpty) {
        lines.add(PurchaseReturnLine(purchaseItemId: i.id, qty: _qty[i.id] ?? 0, imeiUnitIds: units));
      }
    }
    if (lines.isEmpty) return;
    setState(() => _busy = true);
    final r = await guard(context, () => ref.read(purchaseServiceProvider).returnPurchase(
          purchaseId: v.purchase.id,
          lines: lines,
          refundRemainder: _refund,
        ));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      showMessage(context, context.l10n.returnSaved);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final v = widget.view;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: ListView(shrinkWrap: true, children: [
          Text(l.returnItems, style: Theme.of(context).textTheme.titleLarge),
          for (final i in v.items)
            Builder(builder: (context) {
              final units = v.units.where((u) => u.productId == i.productId && u.status == ImeiStatus.inStock).toList();
              if (units.isNotEmpty || v.units.any((u) => u.productId == i.productId)) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.description, style: Theme.of(context).textTheme.titleSmall),
                  for (final u in units)
                    CheckboxListTile(
                      dense: true,
                      value: _imeis.contains(u.id),
                      title: Ltr(Text(u.imei1)),
                      onChanged: (x) => setState(() => x == true ? _imeis.add(u.id) : _imeis.remove(u.id)),
                    ),
                ]);
              }
              final max = i.qty - (v.returned[i.id]?.qty ?? 0);
              final q = _qty[i.id] ?? 0;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(i.description),
                subtitle: Text(l.soldQty(Fmt.qty(i.qty), Fmt.qty(v.returned[i.id]?.qty ?? 0))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(onPressed: q > 0 ? () => setState(() => _qty[i.id] = q - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
                  Text('$q'),
                  IconButton(onPressed: q < max ? () => setState(() => _qty[i.id] = q + 1) : null, icon: const Icon(Icons.add_circle_outline)),
                ]),
              );
            }),
          if (v.purchase.partyId != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_refund ? l.refundNow : l.keepCredit),
              value: _refund,
              onChanged: (x) => setState(() => _refund = x),
            ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: l.save, icon: Icons.check_rounded, loading: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}

/// All purchases, newest first.
class PurchasesListScreen extends ConsumerWidget {
  const PurchasesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.purchases)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_purchase',
        onPressed: () => context.push(Routes.purchaseNew),
        icon: const Icon(Icons.add),
        label: Text(l.newPurchase),
      ),
      body: StreamBuilder<List<Purchase>>(
        stream: (db.select(db.purchases)
              ..where((p) => p.status.equalsValue(DocStatus.reversal).not())
              ..orderBy([(p) => OrderingTerm.desc(p.date)])
              ..limit(200))
            .watch(),
        builder: (context, snap) {
          final rows = snap.data ?? const <Purchase>[];
          if (rows.isEmpty) return EmptyState(icon: Icons.shopping_cart_outlined, title: l.noPurchases, message: '');
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = rows[i];
              return ListTile(
                onTap: () => context.push(Routes.purchaseDetail(p.id)),
                title: Ltr(Text(p.billNo, style: TextStyle(decoration: p.status == DocStatus.reversed ? TextDecoration.lineThrough : null))),
                subtitle: Text(Fmt.dateTime(p.date)),
                trailing: Ltr(Text(Fmt.money(p.total))),
              );
            },
          );
        },
      ),
    );
  }
}
