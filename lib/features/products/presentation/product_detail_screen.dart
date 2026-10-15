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
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/labels.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/money_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/stat_card.dart';

/// Product detail (spec 5.5): current stock, value, movement history and
/// IMEI list with status.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(productsRepoProvider);
    final can = ref.watch(permissionsProvider);
    final theme = Theme.of(context);

    return StreamBuilder<Product?>(
      stream: repo.watchProduct(productId),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return DefaultTabController(
          length: p.tracksImei ? 2 : 1,
          child: Scaffold(
            appBar: AppBar(
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                if (can.editProducts)
                  IconButton(
                    tooltip: l.edit,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => context.push(Routes.productEdit(p.id)),
                  ),
              ],
            ),
            body: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: StreamBuilder<List<StockBalance>>(
                    stream: repo.watchBalances(p.id),
                    builder: (context, bs) {
                      final bal = bs.data ?? const <StockBalance>[];
                      final qty = bal.fold<int>(0, (a, b) => a + b.qtyOnHand);
                      final value = Money.sum(bal.map((b) => b.value));
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Ltr(Text('${p.sku} • ${Fmt.money(p.salePrice)}', style: theme.textTheme.bodyMedium)),
                            const SizedBox(height: AppSpacing.md),
                            Row(children: [
                              Expanded(
                                child: StatCard(
                                  label: l.inStock,
                                  value: Fmt.qty(qty),
                                  tone: qty <= p.minStock ? StatTone.warning : StatTone.neutral,
                                  icon: Icons.inventory_2_outlined,
                                ),
                              ),
                              if (can.seeCost) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(child: StatCard(label: l.stockValue, value: Fmt.money(value), icon: Icons.savings_outlined)),
                              ],
                            ]),
                            if (can.seeCost) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Text('${l.avgCost}: ${Fmt.money(p.avgCost)}', style: theme.textTheme.bodySmall),
                            ],
                            if (can.editProducts) ...[
                              const SizedBox(height: AppSpacing.md),
                              PrimaryButton(
                                label: l.adjustStock,
                                icon: Icons.tune_rounded,
                                outlined: true,
                                onPressed: () => showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => StockAdjustSheet(product: p, currentQty: qty),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: TabBar(tabs: [Tab(text: l.movementHistory), if (p.tracksImei) Tab(text: l.imeiList)]),
                ),
              ],
              body: TabBarView(children: [
                _Movements(productId: p.id, showCost: can.seeCost),
                if (p.tracksImei) _Imeis(productId: p.id, showCost: can.seeCost),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Movements extends ConsumerWidget {
  const _Movements({required this.productId, required this.showCost});

  final String productId;
  final bool showCost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    return StreamBuilder<List<StockMovement>>(
      stream: ref.watch(productsRepoProvider).watchMovements(productId, limit: 200),
      builder: (context, snap) {
        final rows = (snap.data ?? const <StockMovement>[]).where((m) => m.qtyChange != 0).toList();
        if (rows.isEmpty) return Center(child: Text(context.l10n.noMovements));
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final m = rows[i];
            final inbound = m.qtyChange > 0;
            return ListTile(
              dense: true,
              leading: Icon(inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
                  color: inbound ? c.success : c.danger),
              title: Text(context.moveLabel(m.type)),
              subtitle: Text(Fmt.dateTime(m.date)),
              trailing: Ltr(Text(
                '${inbound ? '+' : ''}${Fmt.qty(m.qtyChange)}${showCost ? '  ${Fmt.money(m.unitCost)}' : ''}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: inbound ? c.success : c.danger),
              )),
            );
          },
        );
      },
    );
  }
}

class _Imeis extends ConsumerWidget {
  const _Imeis({required this.productId, required this.showCost});

  final String productId;
  final bool showCost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    return StreamBuilder<List<ImeiUnit>>(
      stream: ref.watch(productsRepoProvider).watchImeis(productId),
      builder: (context, snap) {
        final rows = snap.data ?? const <ImeiUnit>[];
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final u = rows[i];
            final color = u.status == ImeiStatus.inStock ? c.success : c.textSecondary;
            return ListTile(
              dense: true,
              onTap: () => context.push('${Routes.imeiSearch}?q=${u.imei1}'),
              title: Ltr(Text(u.imei1, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
              subtitle: u.imei2 == null ? null : Ltr(Text(u.imei2!)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(context.imeiStatusLabel(u.status), style: TextStyle(color: color)),
                  if (showCost) Ltr(Text(Fmt.money(u.cost), style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Stock adjustment with a reason (spec 5.5). Owner PIN required (spec 9).
class StockAdjustSheet extends ConsumerStatefulWidget {
  const StockAdjustSheet({super.key, required this.product, required this.currentQty});

  final Product product;
  final int currentQty;

  @override
  ConsumerState<StockAdjustSheet> createState() => _StockAdjustSheetState();
}

class _StockAdjustSheetState extends ConsumerState<StockAdjustSheet> {
  AdjustmentReason _reason = AdjustmentReason.damaged;
  final _qty = TextEditingController();
  final _note = TextEditingController();
  String? _imeiUnitId;
  List<ImeiUnit> _units = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.product.tracksImei) {
      ref.read(productsRepoProvider).inStockImeis(widget.product.id).then((u) {
        if (mounted) setState(() => _units = u);
      });
    }
    _qty.text = '';
  }

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final n = int.tryParse(_qty.text.trim());
    if (!widget.product.tracksImei && (n == null || n < 0 || (_reason != AdjustmentReason.countCorrection && n == 0))) {
      showMessage(context, l.invalidNumber);
      return;
    }
    if (widget.product.tracksImei && _imeiUnitId == null) {
      showMessage(context, l.errImeiRequired);
      return;
    }
    if (!await ref.read(pinGateProvider).requireOwner(context) || !mounted) return;
    setState(() => _busy = true);
    final ok = await guard(context, () => ref.read(productServiceProvider).adjustStock(
          productId: widget.product.id,
          reason: _reason,
          qty: n ?? 0,
          countedQty: _reason == AdjustmentReason.countCorrection ? n : null,
          imeiUnitId: _imeiUnitId,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        ));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok != null) {
      showMessage(context, l.adjusted);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final reasons = widget.product.tracksImei
        ? const [AdjustmentReason.damaged, AdjustmentReason.lost]
        : AdjustmentReason.values;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.adjustStock, style: Theme.of(context).textTheme.titleLarge),
            Text('${l.inStock}: ${Fmt.qty(widget.currentQty)}'),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final r in reasons)
                  ChoiceChip(label: Text(context.reasonLabel(r)), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (widget.product.tracksImei)
              DropdownButtonFormField<String>(
                initialValue: _imeiUnitId,
                decoration: InputDecoration(labelText: l.selectImei),
                items: [for (final u in _units) DropdownMenuItem(value: u.id, child: Ltr(Text(u.imei1)))],
                onChanged: (v) => setState(() => _imeiUnitId = v),
              )
            else
              IntField(
                controller: _qty,
                label: _reason == AdjustmentReason.countCorrection ? l.countedQty : l.quantity,
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _note, decoration: InputDecoration(labelText: l.reasonNote)),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(label: l.save, icon: Icons.check_rounded, loading: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
