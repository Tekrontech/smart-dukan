import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../app/providers.dart';
import '../../../../app/router.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/pdf/pdf_kit.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/files.dart';
import '../../../../core/utils/fmt.dart';
import '../../../../core/widgets/amount_keypad.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/labels.dart';
import '../../../../core/widgets/ltr.dart';
import '../../../../core/widgets/money_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/pro_gate.dart';
import '../../../../core/widgets/scanner.dart';
import '../../../license/presentation/license_screen.dart' show openWhatsApp;
import '../../../parties/presentation/party_picker.dart';
import '../../../products/presentation/product_picker.dart';
import '../application/repair_service.dart';

String repairStatusLabel(BuildContext context, RepairStatus s) {
  final l = context.l10n;
  return switch (s) {
    RepairStatus.received => l.rsReceived,
    RepairStatus.diagnosing => l.rsDiagnosing,
    RepairStatus.waitingParts => l.rsWaitingParts,
    RepairStatus.ready => l.rsReady,
    RepairStatus.delivered => l.rsDelivered,
    RepairStatus.returnedUnrepaired => l.rsReturned,
  };
}

bool _closed(RepairStatus s) => s == RepairStatus.delivered || s == RepairStatus.returnedUnrepaired;

class RepairsListScreen extends ConsumerWidget {
  const RepairsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final db = ref.watch(databaseProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.repairJobs),
          bottom: TabBar(tabs: [Tab(text: l.openJobs), Tab(text: l.closedJobs)]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'repair_new',
          onPressed: () async {
            if (await requirePro(context, ref) && context.mounted) context.push(Routes.repairNew);
          },
          icon: const Icon(Icons.add),
          label: Text(l.repairNew),
        ),
        body: StreamBuilder<List<RepairJob>>(
          stream: (db.select(db.repairJobs)..orderBy([(j) => OrderingTerm.desc(j.createdAt)])).watch(),
          builder: (context, snap) {
            final all = snap.data ?? const <RepairJob>[];
            Widget list(List<RepairJob> jobs) => jobs.isEmpty
                ? EmptyState(icon: Icons.build_outlined, title: l.noRepairs, message: '')
                : ListView.separated(
                    itemCount: jobs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final j = jobs[i];
                      return ListTile(
                        onTap: () => context.push(Routes.repair(j.id)),
                        leading: CircleAvatar(child: Icon(_closed(j.status) ? Icons.done_all_rounded : Icons.build_rounded, size: 20)),
                        title: Text('${j.deviceModel} • ${j.problem}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Ltr(Text('${j.jobNo} • ${Fmt.date(j.createdAt)}')),
                        trailing: Chip(label: Text(repairStatusLabel(context, j.status))),
                      );
                    },
                  );
            return TabBarView(children: [
              list(all.where((j) => !_closed(j.status)).toList()),
              list(all.where((j) => _closed(j.status)).toList()),
            ]);
          },
        ),
      ),
    );
  }
}

class RepairFormScreen extends ConsumerStatefulWidget {
  const RepairFormScreen({super.key});

  @override
  ConsumerState<RepairFormScreen> createState() => _RepairFormScreenState();
}

class _RepairFormScreenState extends ConsumerState<RepairFormScreen> {
  final _form = GlobalKey<FormState>();
  final _device = TextEditingController();
  final _imei = TextEditingController();
  final _problem = TextEditingController();
  final _estimate = TextEditingController();
  final _advance = TextEditingController();
  String? _partyId;
  String? _partyName;
  String? _techId;
  DateTime? _expected;
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_device, _imei, _problem, _estimate, _advance]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (!_form.currentState!.validate()) return;
    if (_partyId == null) return showMessage(context, l.errPartyRequired);
    setState(() => _busy = true);
    final r = await guard(context, () => ref.read(repairServiceProvider).createJob(
          partyId: _partyId!,
          deviceModel: _device.text,
          imei: _imei.text,
          problem: _problem.text,
          estimate: MoneyField.read(_estimate) ?? Money.zero,
          advance: MoneyField.read(_advance) ?? Money.zero,
          advanceMethod: _method,
          technicianId: _techId,
          expectedDate: _expected,
        ));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      savedHaptic();
      showMessage(context, l.repairSaved);
      context.pushReplacement(Routes.repair(r.jobId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.repairNew)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(_partyName ?? l.chooseCustomer),
                subtitle: Text(l.customer),
                onTap: () async {
                  final p = await pickParty(context, allowWalkIn: false);
                  if (p?.id != null) {
                    setState(() {
                      _partyId = p!.id;
                      _partyName = p.name;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _device,
              decoration: InputDecoration(labelText: l.colDevice),
              validator: (v) => (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            Ltr(TextFormField(
              controller: _imei,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'IMEI (${l.optional})',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  onPressed: () async {
                    final c = await scanCode(context);
                    if (c != null) _imei.text = c;
                  },
                ),
              ),
            )),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _problem,
              maxLines: 2,
              decoration: InputDecoration(labelText: l.problem),
              validator: (v) => (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(child: MoneyField(controller: _estimate, label: l.estimate)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: MoneyField(controller: _advance, label: l.advance)),
            ]),
            Wrap(spacing: AppSpacing.sm, children: [
              for (final m in PaymentMethod.values)
                ChoiceChip(label: Text(context.methodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
            ]),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(l.expectedDate),
              trailing: Text(_expected == null ? '-' : Fmt.date(_expected!)),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, firstDate: now, lastDate: DateTime(now.year + 1), initialDate: now);
                if (d != null) setState(() => _expected = d);
              },
            ),
            StreamBuilder<List<AppUser>>(
              stream: (db.select(db.users)..where((u) => u.isActive.equals(true))).watch(),
              builder: (context, s) => DropdownButtonFormField<String?>(
                initialValue: _techId,
                decoration: InputDecoration(labelText: l.technician),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.none)),
                  for (final u in s.data ?? const <AppUser>[]) DropdownMenuItem(value: u.id, child: Text(u.name)),
                ],
                onChanged: (v) => setState(() => _techId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: l.save, icon: Icons.check_rounded, loading: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _RepairView {
  const _RepairView(this.job, this.party, this.parts, this.log, this.balance, this.products);

  final RepairJob job;
  final Party party;
  final List<RepairPart> parts;
  final List<RepairStatusLog> log;
  final Money balance;
  final Map<String, String> products;
}

final _repairProvider = StreamProvider.autoDispose.family<_RepairView?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  Future<_RepairView?> load() async {
    final job = await (db.select(db.repairJobs)..where((j) => j.id.equals(id))).getSingleOrNull();
    if (job == null) return null;
    final party = await (db.select(db.parties)..where((p) => p.id.equals(job.partyId))).getSingle();
    final parts = await (db.select(db.repairParts)..where((p) => p.jobId.equals(id))..orderBy([(p) => OrderingTerm.asc(p.createdAt)])).get();
    final log = await (db.select(db.repairStatusLogs)..where((p) => p.jobId.equals(id))..orderBy([(p) => OrderingTerm.asc(p.createdAt)])).get();
    final products = {
      for (final p in await (db.select(db.products)..where((x) => x.id.isIn(parts.map((e) => e.productId)))).get()) p.id: p.name
    };
    return _RepairView(job, party, parts, log, await ref.read(ledgerProvider).refBalance(id), products);
  }

  return (() async* {
    yield await load();
    await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables([db.repairJobs, db.repairParts, db.journalLines]))) {
      yield await load();
    }
  })();
});

class RepairDetailScreen extends ConsumerWidget {
  const RepairDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final v = ref.watch(_repairProvider(jobId)).value;
    if (v == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final j = v.job;
    final svc = ref.read(repairServiceProvider);
    final open = !_closed(j.status);

    Future<Money?> keypad(String title, [Money? initial]) => AmountKeypad.show(context, title: title, doneLabel: l.done, initial: initial);

    return Scaffold(
      appBar: AppBar(
        title: Ltr(Text(j.jobNo)),
        actions: [
          IconButton(
            tooltip: l.tokenSlip,
            icon: const Icon(Icons.confirmation_number_outlined),
            onPressed: () => guard(context, () async {
              final pdf = await _tokenSlip(ref, v);
              await shareBytes('${j.jobNo}.pdf', pdf, mimeType: 'application/pdf');
            }),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(j.deviceModel, style: theme.textTheme.titleLarge),
                if (j.imei != null) Ltr(Text('IMEI ${j.imei}')),
                Text(j.problem),
                const SizedBox(height: AppSpacing.sm),
                Text('${v.party.name}${v.party.phone == null ? '' : ' • ${v.party.phone}'}'),
                if (!j.estimate.isZero) Text('${l.estimate}: ${Fmt.money(j.estimate)}'),
                if (j.expectedDate != null) Text('${l.expectedDate}: ${Fmt.date(j.expectedDate!)}'),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  Chip(label: Text(repairStatusLabel(context, j.status))),
                  const Spacer(),
                  Text('${l.outstanding}: ', style: theme.textTheme.bodySmall),
                  Ltr(Text(Fmt.money(v.balance),
                      style: theme.textTheme.titleMedium?.copyWith(color: v.balance.isPositive ? c.danger : (v.balance.isNegative ? c.success : null)))),
                ]),
              ]),
            ),
          ),
          if (open) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(l.moveTo, style: theme.textTheme.titleSmall),
            Wrap(spacing: AppSpacing.sm, children: [
              for (final s in RepairService.transitions[j.status] ?? const <RepairStatus>{})
                ActionChip(label: Text(repairStatusLabel(context, s)), onPressed: () => guard(context, () => svc.changeStatus(j.id, s))),
            ]),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: Text(l.parts, style: theme.textTheme.titleSmall)),
            if (open)
              TextButton.icon(
                onPressed: () async {
                  final h = await pickProduct(context, excludeImei: true);
                  if (h == null || !context.mounted) return;
                  final charge = await keypad(l.partCharge, h.price);
                  if (!context.mounted) return;
                  await guard(context, () => svc.issuePart(j.id, productId: h.product.id, variantId: h.variant?.id, charge: charge ?? Money.zero));
                },
                icon: const Icon(Icons.add),
                label: Text(l.issuePart),
              ),
          ]),
          for (final p in v.parts)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(p.action == RepairPartAction.issued ? Icons.north_east_rounded : Icons.south_west_rounded),
              title: Text(v.products[p.productId] ?? ''),
              subtitle: Text('${p.action == RepairPartAction.issued ? l.issuePart : l.returnPart} • ${p.qty}'),
              trailing: open && p.action == RepairPartAction.issued
                  ? IconButton(
                      tooltip: l.returnPart,
                      icon: const Icon(Icons.undo_rounded),
                      onPressed: () => guard(context, () => svc.returnPart(j.id, productId: p.productId, variantId: p.variantId)),
                    )
                  : (p.charge.isZero ? null : Ltr(Text(Fmt.money(p.charge)))),
            ),
          const Divider(height: AppSpacing.xl),
          if (open) ...[
            PrimaryButton(
              label: l.deliver,
              icon: Icons.handshake_outlined,
              onPressed: () async {
                final partsCharge = Money.sum(v.parts.where((p) => p.action == RepairPartAction.issued).map((p) => p.charge));
                final bill = await keypad(l.finalBill, Money.max(j.estimate, partsCharge));
                if (bill == null || !context.mounted) return;
                final due = bill + v.balance;
                final paid = due.isPositive ? await keypad(l.paidNow, due) : Money.zero;
                if (paid == null || !context.mounted) return;
                final ok = await guard(context, () async {
                  await svc.deliver(j.id, finalAmount: bill, paidNow: paid);
                  return true;
                });
                if (ok != null) savedHaptic();
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: l.returnUnrepaired,
              icon: Icons.assignment_return_outlined,
              outlined: true,
              onPressed: () async {
                final fee = await keypad(l.inspectionFee);
                if (fee == null || !context.mounted) return;
                await guard(context, () => svc.returnUnrepaired(j.id, fee: fee));
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: l.advance,
              icon: Icons.add_card_outlined,
              outlined: true,
              onPressed: () async {
                final a = await keypad(l.advance);
                if (a == null || !a.isPositive || !context.mounted) return;
                await guard(context, () => svc.addAdvance(j.id, a));
              },
            ),
          ],
          if (j.status == RepairStatus.ready) ...[
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: l.sendReady,
              icon: Icons.chat_rounded,
              outlined: true,
              onPressed: () => openWhatsApp(
                l.readyMessage(v.party.name, j.deviceModel, j.jobNo,
                    MoneyFormat.format(Money.max(j.estimate + v.balance, Money.zero), symbol: false, urduDigits: false),
                    ref.read(sessionProvider).business!.name),
                phone: v.party.phone,
              ),
            ),
          ],
          if (v.balance.isPositive && !open) ...[
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: l.collectPayment,
              icon: Icons.south_west_rounded,
              onPressed: () async {
                final a = await keypad(l.collectPayment, v.balance);
                if (a == null || !context.mounted) return;
                await guard(context, () => svc.collect(j.id, a));
              },
            ),
          ],
          if (v.balance.isNegative) ...[
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: l.refundAdvance,
              icon: Icons.north_east_rounded,
              outlined: true,
              onPressed: () async {
                final a = await keypad(l.refundAdvance, -v.balance);
                if (a == null || !context.mounted) return;
                await guard(context, () => svc.refundAdvance(j.id, a));
              },
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(l.history, style: theme.textTheme.titleSmall),
          for (final e in v.log)
            Text('${Fmt.dateTime(e.createdAt)} • ${repairStatusLabel(context, e.toStatus)}', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Future<Uint8List> _tokenSlip(WidgetRef ref, _RepairView v) async {
    final k = await PdfKit.load();
    final b = ref.read(sessionProvider).business!;
    final j = v.job;
    final doc = pw.Document(theme: k.theme());
    doc.addPage(pw.Page(
      pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        k.header(b, compact: true, title: 'Repair token'),
        pw.Divider(color: PdfKit.line),
        k.kv('Job', j.jobNo, strong: true, size: 12),
        k.kv('Date', Fmt.dateTime(j.createdAt)),
        k.kv('Customer', v.party.name),
        k.kv('Device', j.deviceModel),
        if (j.imei != null) k.kv('IMEI', j.imei!),
        pw.Text('Problem: ${j.problem}', style: const pw.TextStyle(fontSize: 9)),
        if (!j.estimate.isZero) k.kv('Estimate', PdfKit.money(j.estimate)),
        if (j.expectedDate != null) k.kv('Ready by', Fmt.date(j.expectedDate!)),
        k.kv('Balance', PdfKit.money(v.balance), strong: true),
        k.footer('Bring this token when collecting your device.'),
      ]),
    ));
    return doc.save();
  }
}
