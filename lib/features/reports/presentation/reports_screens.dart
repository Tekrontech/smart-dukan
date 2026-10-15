import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart' as csvlib;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/pdf/pdf_kit.dart';
import '../../../core/security/pin_gate.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/files.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/pro_gate.dart';
import '../application/reports_service.dart';

String reportTitle(BuildContext context, ReportKind k) {
  final l = context.l10n;
  return switch (k) {
    ReportKind.daily => l.reportDaily,
    ReportKind.salesByItem => l.reportSalesItem,
    ReportKind.salesByCategory => l.reportSalesCategory,
    ReportKind.salesByStaff => l.reportSalesStaff,
    ReportKind.pnl => l.reportPnl,
    ReportKind.stockValue => l.reportStockValue,
    ReportKind.lowStock => l.reportLowStock,
    ReportKind.customerAgeing => l.reportAgeing,
    ReportKind.supplierDues => l.reportSupplierDues,
    ReportKind.expenses => l.reportExpenses,
    ReportKind.cashBook => l.reportCashBook,
    ReportKind.imeiSold => l.reportImeiSold,
    ReportKind.repairs => l.reportRepairs,
    ReportKind.qist => l.reportQist,
  };
}

IconData _icon(ReportKind k) => switch (k) {
      ReportKind.daily => Icons.today_rounded,
      ReportKind.salesByItem || ReportKind.salesByCategory || ReportKind.salesByStaff => Icons.trending_up_rounded,
      ReportKind.pnl => Icons.account_balance_outlined,
      ReportKind.stockValue || ReportKind.lowStock => Icons.inventory_2_outlined,
      ReportKind.customerAgeing || ReportKind.supplierDues => Icons.people_outline_rounded,
      ReportKind.expenses => Icons.receipt_long_outlined,
      ReportKind.cashBook => Icons.menu_book_rounded,
      ReportKind.imeiSold => Icons.phone_android_rounded,
      ReportKind.repairs => Icons.build_outlined,
      ReportKind.qist => Icons.event_repeat_rounded,
    };

ReportLabels reportLabels(BuildContext context) {
  final l = context.l10n;
  return ReportLabels(
    date: l.date,
    salesCount: l.salesCount,
    total: l.total,
    paid: l.paid,
    udhaar: l.payUdhaar,
    grossProfit: l.grossProfit,
    expenses: l.expensesTotal,
    item: l.colItem,
    category: l.category,
    staff: l.colStaff,
    qtySold: l.qtySold,
    amount: l.amountLabel,
    cost: l.cost,
    profit: l.profitLabel,
    grossSales: l.grossSales,
    returns: l.returnsLabel,
    discounts: l.discountsLabel,
    netSales: l.netSales,
    cogs: l.cogsLabel,
    otherIncome: l.otherIncome,
    netProfit: l.netProfit,
    details: l.details,
    sku: l.sku,
    qty: l.quantity,
    avgCost: l.avgCost,
    stockValue: l.stockValue,
    saleValue: l.colSaleValue,
    minStock: l.minStockAlert,
    customer: l.customer,
    age0: l.age0to30,
    age31: l.age31to60,
    age61: l.age61to90,
    age90: l.age90plus,
    other: l.colOther,
    supplier: l.supplier,
    phone: l.phone,
    dena: l.dena,
    count: l.colCount,
    opening: l.openingLabel,
    closing: l.closingLabel,
    inflow: l.inflow,
    outflow: l.outflow,
    balance: l.balance,
    invoice: l.invoice,
    walkIn: l.walkInCustomer,
    jobNo: l.colJobNo,
    device: l.colDevice,
    status: l.status,
    collected: l.collected,
    overdue: l.overdue,
    nextDue: l.colNextDue,
    // Capture strings now: these run after the await, when the context may be gone.
    expenseCategory: (key, name) => switch (key) {
      'rent' => l.catRent,
      'bijli' => l.catBijli,
      'salary' => l.catSalary,
      'chai_pani' => l.catChai,
      'transport' => l.catTransport,
      'other' => l.catOther,
      _ => name,
    },
    repairStatus: (s) => switch (s) {
      'received' => l.rsReceived,
      'diagnosing' => l.rsDiagnosing,
      'waitingParts' => l.rsWaitingParts,
      'ready' => l.rsReady,
      'delivered' => l.rsDelivered,
      'returnedUnrepaired' => l.rsReturned,
      _ => s,
    },
  );
}

/// Reports hub (spec 5.10).
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final pro = ref.watch(proActiveProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(l.reports)),
      body: ListView(
        children: [
          for (final k in ReportKind.values)
            ListTile(
              key: Key('report_${k.name}'),
              leading: Icon(_icon(k), color: c.primary),
              title: Text(reportTitle(context, k)),
              trailing: k.isPro && !pro
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(6)),
                      child: Text(l.proBadge, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.light.textPrimary)),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                if (k.isPro && !await requirePro(context, ref)) return;
                if (context.mounted) context.push(Routes.report(k.name));
              },
            ),
        ],
      ),
    );
  }
}

enum _Range { today, yesterday, week, month, custom }

/// One report with a date-range picker and PDF / CSV export.
class ReportViewScreen extends ConsumerStatefulWidget {
  const ReportViewScreen({super.key, required this.kind});

  final ReportKind kind;

  @override
  ConsumerState<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends ConsumerState<ReportViewScreen> {
  _Range _range = _Range.today;
  late DateTime _from;
  late DateTime _to;
  Future<ReportTable>? _future;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Labels need localizations, which are not available in initState.
    if (!_started) {
      _started = true;
      _setRange(widget.kind == ReportKind.pnl || widget.kind == ReportKind.expenses ? _Range.month : _Range.today);
    }
  }

  void _setRange(_Range r, [DateTimeRange? custom]) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final (from, to) = switch (r) {
      _Range.today => (today, today.add(const Duration(days: 1))),
      _Range.yesterday => (today.subtract(const Duration(days: 1)), today),
      _Range.week => (today.subtract(Duration(days: today.weekday - 1)), today.add(const Duration(days: 1))),
      _Range.month => (DateTime(now.year, now.month), today.add(const Duration(days: 1))),
      _Range.custom => (custom!.start, custom.end.add(const Duration(days: 1))),
    };
    _from = from;
    _to = to;
    _range = r;
    _load();
  }

  void _load() {
    final labels = reportLabels(context);
    final f = ReportsService(ref.read(databaseProvider)).run(widget.kind, _from, _to, labels);
    if (mounted) {
      setState(() {
        _future = f;
      });
    }
  }

  String get _period => '${Fmt.date(_from)} – ${Fmt.date(_to.subtract(const Duration(days: 1)))}';

  /// Spec 9: owner PIN for full reports + one-time "contains business data"
  /// warning.
  Future<bool> _exportAllowed() async {
    final l = context.l10n;
    if (!await ref.read(pinGateProvider).requireOwner(context, reason: l.fullReportPin)) return false;
    final settings = ref.read(settingsRepoProvider);
    if (!await settings.getBool(SettingKeys.exportWarningShown)) {
      if (!mounted) return false;
      final ok = await ConfirmSheet.show(context,
          title: l.exportPdf, message: l.exportWarning, confirmLabel: l.continueAnyway, cancelLabel: l.cancel);
      if (!ok) return false;
      await settings.set(SettingKeys.exportWarningShown, 'true');
    }
    return true;
  }

  Future<void> _exportPdf(ReportTable t) async {
    if (!await _exportAllowed() || !mounted) return;
    final title = reportTitle(context, widget.kind);
    final business = ref.read(sessionProvider).business!;
    await guard(context, () async {
      final k = await PdfKit.load();
      final pdf = await k.a4(business, title, widget.kind.isSnapshot ? Fmt.date(DateTime.now()) : _period, [
        k.table(t.headers, [...t.rows, ?t.totals], rightAligned: t.numeric),
      ]);
      await shareBytes('${widget.kind.name}_${Fmt.fileStamp(DateTime.now())}.pdf', pdf, mimeType: 'application/pdf');
    });
  }

  Future<void> _exportCsv(ReportTable t) async {
    if (!await _exportAllowed() || !mounted) return;
    await guard(context, () async {
      final text = csvlib.Csv(lineDelimiter: '\n', addBom: true).encode([t.headers, ...t.rows, ?t.totals]);
      await shareBytes('${widget.kind.name}_${Fmt.fileStamp(DateTime.now())}.csv', Uint8List.fromList(utf8.encode(text)),
          mimeType: 'text/csv');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<ReportTable>(
      future: _future,
      builder: (context, snap) {
        final t = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(reportTitle(context, widget.kind)),
            actions: [
              IconButton(tooltip: l.exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: t == null ? null : () => _exportPdf(t)),
              IconButton(tooltip: l.exportCsv, icon: const Icon(Icons.table_view_outlined), onPressed: t == null ? null : () => _exportCsv(t)),
            ],
          ),
          body: Column(
            children: [
              if (!widget.kind.isSnapshot)
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    children: [
                      for (final r in _Range.values)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                          child: ChoiceChip(
                            label: Text(switch (r) {
                              _Range.today => l.today,
                              _Range.yesterday => l.yesterday,
                              _Range.week => l.thisWeek,
                              _Range.month => l.thisMonth,
                              _Range.custom => _range == _Range.custom ? _period : l.customRange,
                            }),
                            selected: _range == r,
                            onSelected: (_) async {
                              if (r == _Range.custom) {
                                final now = DateTime.now();
                                final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(now.year + 1));
                                if (picked != null) _setRange(r, picked);
                              } else {
                                _setRange(r);
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: t == null
                    ? (snap.hasError ? Center(child: Text(l.errGeneric)) : const Center(child: CircularProgressIndicator()))
                    : ListView(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        children: [
                          if (t.summary.isNotEmpty)
                            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                              for (final s in t.summary)
                                Chip(label: Text('${s.$1}: Rs ${s.$2}', style: theme.textTheme.titleSmall)),
                            ]),
                          if (t.rows.isEmpty)
                            Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: Center(child: Text(l.reportEmpty)))
                          else
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: WidgetStatePropertyAll(c.primaryContainer),
                                columnSpacing: AppSpacing.lg,
                                dataRowMinHeight: 40,
                                columns: [
                                  for (var i = 0; i < t.headers.length; i++)
                                    DataColumn(label: Text(t.headers[i]), numeric: t.numeric.contains(i)),
                                ],
                                rows: [
                                  for (final r in t.rows) DataRow(cells: [for (final cell in r) DataCell(Text(cell))]),
                                  if (t.totals != null)
                                    DataRow(
                                      color: WidgetStatePropertyAll(c.background),
                                      cells: [for (final cell in t.totals!) DataCell(Text(cell, style: theme.textTheme.titleSmall))],
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
