import 'package:drift/drift.dart' show OrderingTerm, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../app/router.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/fmt.dart';
import '../../../../core/widgets/labels.dart';
import '../../../../core/widgets/ltr.dart';
import '../../../../core/widgets/scanner.dart';

class _ImeiHistory {
  _ImeiHistory(this.unit, this.product);

  final ImeiUnit unit;
  final Product product;
  String? purchasedFrom;
  DateTime? boughtOn;
  Sale? sale;
  String? soldTo;
  List<RepairJob> repairs = const [];
  List<StockMovement> moves = const [];
}

/// IMEI search (spec 5.9): purchased from, cost, sold to, date, warranty,
/// repairs. Readable even without Pro (records are never locked).
class ImeiSearchScreen extends ConsumerStatefulWidget {
  const ImeiSearchScreen({super.key, this.initial});

  final String? initial;

  @override
  ConsumerState<ImeiSearchScreen> createState() => _ImeiSearchScreenState();
}

class _ImeiSearchScreenState extends ConsumerState<ImeiSearchScreen> {
  late final _q = TextEditingController(text: widget.initial ?? '');
  List<_ImeiHistory>? _results;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    final db = ref.read(databaseProvider);
    final units = await (db.select(db.imeiUnits)
          ..where((u) => u.imei1.equals(q) | u.imei2.equals(q) | u.serial.equals(q))
          ..orderBy([(u) => OrderingTerm.desc(u.createdAt)]))
        .get();
    final out = <_ImeiHistory>[];
    for (final u in units) {
      final p = await (db.select(db.products)..where((x) => x.id.equals(u.productId))).getSingle();
      final h = _ImeiHistory(u, p);
      if (u.purchaseRefType == 'purchase' && u.purchaseRefId != null) {
        final pur = await (db.select(db.purchases)..where((x) => x.id.equals(u.purchaseRefId!))).getSingleOrNull();
        h.boughtOn = pur?.date;
        if (pur?.partyId != null) {
          h.purchasedFrom = (await (db.select(db.parties)..where((x) => x.id.equals(pur!.partyId!))).getSingleOrNull())?.name;
        }
      } else if (u.purchaseRefType == 'used_phone' && u.purchaseRefId != null) {
        final up = await (db.select(db.usedPhonePurchases)..where((x) => x.id.equals(u.purchaseRefId!))).getSingleOrNull();
        h.boughtOn = up?.date;
        if (up != null) {
          h.purchasedFrom = (await (db.select(db.parties)..where((x) => x.id.equals(up.sellerPartyId))).getSingleOrNull())?.name;
        }
      } else {
        h.boughtOn = u.createdAt;
      }
      if (u.saleRefId != null) {
        h.sale = await (db.select(db.sales)..where((x) => x.id.equals(u.saleRefId!))).getSingleOrNull();
        if (h.sale?.partyId != null) {
          h.soldTo = (await (db.select(db.parties)..where((x) => x.id.equals(h.sale!.partyId!))).getSingleOrNull())?.name;
        }
      }
      h.repairs = await (db.select(db.repairJobs)..where((j) => j.imei.equals(u.imei1) | j.imei.equals(u.imei2 ?? '-'))).get();
      h.moves = await (db.select(db.stockMovements)
            ..where((m) => m.imeiUnitId.equals(u.id))
            ..orderBy([(m) => OrderingTerm.asc(m.date)]))
          .get();
      out.add(h);
    }
    if (mounted) setState(() => _results = out);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final seeCost = ref.watch(permissionsProvider).seeCost;
    final results = _results;
    return Scaffold(
      appBar: AppBar(title: Text(l.imeiSearch)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Ltr(TextField(
            key: const Key('imei_query'),
            controller: _q,
            keyboardType: TextInputType.number,
            autofocus: widget.initial == null,
            decoration: InputDecoration(
              hintText: l.imeiSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded),
                onPressed: () async {
                  final code = await scanCode(context);
                  if (code != null) {
                    _q.text = code;
                    _search();
                  }
                },
              ),
            ),
            onSubmitted: (_) => _search(),
          )),
          const SizedBox(height: AppSpacing.md),
          if (results != null && results.isEmpty) Center(child: Text(l.imeiNotFound)),
          for (final h in results ?? const <_ImeiHistory>[])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(h.product.name, style: theme.textTheme.titleMedium)),
                    Chip(label: Text(context.imeiStatusLabel(h.unit.status))),
                  ]),
                  Ltr(Text('IMEI ${h.unit.imei1}${h.unit.imei2 == null ? '' : ' / ${h.unit.imei2}'}')),
                  const Divider(),
                  _kv(context, l.purchasedFrom, h.purchasedFrom ?? l.openingStockSource),
                  if (h.boughtOn != null) _kv(context, l.boughtOn, Fmt.date(h.boughtOn!)),
                  if (seeCost) _kv(context, l.cost, Fmt.money(h.unit.cost)),
                  if (h.unit.conditionGrade != null) _kv(context, l.grade, h.unit.conditionGrade!.name.toUpperCase()),
                  if (h.sale != null) ...[
                    _kv(context, l.soldTo, h.soldTo ?? l.walkInCustomer),
                    _kv(context, l.soldOn, Fmt.date(h.sale!.date)),
                    InkWell(
                      onTap: () => context.push(Routes.saleDetail(h.sale!.id)),
                      child: _kv(context, l.invoice, h.sale!.invoiceNo, link: true),
                    ),
                  ],
                  if (h.unit.warrantyUntil != null)
                    _kv(context, l.warranty, Fmt.date(h.unit.warrantyUntil!),
                        color: h.unit.warrantyUntil!.isAfter(DateTime.now()) ? c.success : c.danger),
                  for (final j in h.repairs)
                    InkWell(
                      onTap: () => context.push(Routes.repair(j.id)),
                      child: _kv(context, l.repairJobs, '${j.jobNo} • ${Fmt.date(j.createdAt)}', link: true),
                    ),
                  if (h.moves.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(l.history, style: theme.textTheme.titleSmall),
                    for (final m in h.moves.where((m) => m.qtyChange != 0))
                      Text('${Fmt.date(m.date)} • ${context.moveLabel(m.type)} ${m.qtyChange > 0 ? '+' : ''}${m.qtyChange}',
                          style: theme.textTheme.bodySmall),
                  ],
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {Color? color, bool link = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k, style: Theme.of(context).textTheme.bodySmall)),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.end,
                style: TextStyle(color: link ? AppColors.of(context).primary : color, decoration: link ? TextDecoration.underline : null)),
          ),
        ]),
      );
}
