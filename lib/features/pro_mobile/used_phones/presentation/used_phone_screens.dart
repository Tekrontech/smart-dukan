import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../app/providers.dart';
import '../../../../app/router.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/pdf/pdf_kit.dart';
import '../../../../core/security/pin_gate.dart';
import '../../../../core/security/secure_screen.dart';
import '../../../../core/settings/settings_repository.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/fmt.dart';
import '../../../../core/widgets/confirm_sheet.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/labels.dart';
import '../../../../core/widgets/ltr.dart';
import '../../../../core/widgets/money_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/pro_gate.dart';
import '../../../../core/widgets/scanner.dart';
import '../../../parties/presentation/party_picker.dart';
import '../../../products/presentation/product_picker.dart';

String gradeLabel(BuildContext context, ConditionGrade g) => switch (g) {
      ConditionGrade.a => context.l10n.gradeA,
      ConditionGrade.b => context.l10n.gradeB,
      ConditionGrade.c => context.l10n.gradeC,
    };

class UsedPhonesListScreen extends ConsumerWidget {
  const UsedPhonesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.usedPhones)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'used_new',
        onPressed: () async {
          if (await requirePro(context, ref) && context.mounted) context.push(Routes.usedPhoneNew);
        },
        icon: const Icon(Icons.add),
        label: Text(l.usedPhoneNew),
      ),
      body: StreamBuilder<List<UsedPhonePurchase>>(
        stream: (db.select(db.usedPhonePurchases)
              ..where((u) => u.status.equalsValue(DocStatus.reversal).not())
              ..orderBy([(u) => OrderingTerm.desc(u.date)]))
            .watch(),
        builder: (context, snap) {
          final rows = snap.data ?? const <UsedPhonePurchase>[];
          if (rows.isEmpty) return EmptyState(icon: Icons.phone_android_rounded, title: l.noUsedPhones, message: '');
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final u = rows[i];
              return ListTile(
                onTap: () => context.push(Routes.usedPhone(u.id)),
                title: Text(u.model, style: TextStyle(decoration: u.status == DocStatus.reversed ? TextDecoration.lineThrough : null)),
                subtitle: Ltr(Text('${u.docNo} • ${Fmt.date(u.date)} • ${u.grade.name.toUpperCase()}')),
                trailing: Ltr(Text(Fmt.money(u.price))),
              );
            },
          );
        },
      ),
    );
  }
}

/// Used phone purchase (spec 5.9). CNIC number and photos are optional and
/// only shown when the shop switched them on (spec 9); photos are stored
/// encrypted and the screen is FLAG_SECURE.
class UsedPhoneFormScreen extends ConsumerStatefulWidget {
  const UsedPhoneFormScreen({super.key});

  @override
  ConsumerState<UsedPhoneFormScreen> createState() => _UsedPhoneFormScreenState();
}

class _UsedPhoneFormScreenState extends ConsumerState<UsedPhoneFormScreen> {
  final _form = GlobalKey<FormState>();
  final _model = TextEditingController();
  final _imei1 = TextEditingController();
  final _imei2 = TextEditingController();
  final _price = TextEditingController();
  final _cnic = TextEditingController();
  String? _sellerId;
  String? _sellerName;
  String? _productId;
  String? _productName;
  ConditionGrade _grade = ConditionGrade.b;
  PaymentMethod _method = PaymentMethod.cash;
  String? _front;
  String? _back;
  final List<String> _photos = [];
  bool _cnicOn = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(settingsRepoProvider).getBool(SettingKeys.cnicEnabled).then((v) {
      if (mounted) setState(() => _cnicOn = v);
    });
  }

  @override
  void dispose() {
    for (final c in [_model, _imei1, _imei2, _price, _cnic]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _photo() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 70);
    if (x == null) return null;
    return ref.read(photoVaultProvider).save(await x.readAsBytes());
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (!_form.currentState!.validate()) return;
    if (_sellerId == null) return showMessage(context, l.chooseSeller);
    if (_productId == null) return showMessage(context, l.usedProduct);
    setState(() => _busy = true);
    final r = await guard(context, () => ref.read(usedPhoneServiceProvider).purchase(
          sellerPartyId: _sellerId!,
          productId: _productId!,
          model: _model.text.trim(),
          imei1: _imei1.text.trim(),
          imei2: _imei2.text.trim().isEmpty ? null : _imei2.text.trim(),
          grade: _grade,
          price: MoneyField.read(_price)!,
          method: _method,
          sellerCnic: _cnic.text.trim().isEmpty ? null : _cnic.text.trim(),
          cnicFrontPath: _front,
          cnicBackPath: _back,
          devicePhotoPaths: _photos,
        ));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      savedHaptic();
      showMessage(context, l.usedPhoneSaved);
      context.pushReplacement(Routes.usedPhone(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SecureArea(
      child: Scaffold(
        appBar: AppBar(title: Text(l.usedPhoneNew)),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(_sellerName ?? l.chooseSeller),
                  subtitle: Text(l.seller),
                  onTap: () async {
                    final p = await pickParty(context, allowWalkIn: false);
                    if (p?.id != null) {
                      setState(() {
                        _sellerId = p!.id;
                        _sellerName = p.name;
                      });
                    }
                  },
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(_productName ?? l.usedProduct),
                  onTap: () async {
                    final h = await pickProduct(context, imeiOnly: true);
                    if (h != null) {
                      setState(() {
                        _productId = h.product.id;
                        _productName = h.product.name;
                        if (_model.text.isEmpty) _model.text = h.product.name;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _model,
                decoration: InputDecoration(labelText: l.model),
                validator: (v) => (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Ltr(TextFormField(
                controller: _imei1,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l.imei1,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    onPressed: () async {
                      final c = await scanCode(context);
                      if (c != null) _imei1.text = c;
                    },
                  ),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
              )),
              const SizedBox(height: AppSpacing.sm),
              Ltr(TextFormField(controller: _imei2, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.imei2))),
              const SizedBox(height: AppSpacing.md),
              Text(l.grade, style: Theme.of(context).textTheme.titleSmall),
              Wrap(spacing: AppSpacing.sm, children: [
                for (final g in ConditionGrade.values)
                  ChoiceChip(label: Text(gradeLabel(context, g)), selected: _grade == g, onSelected: (_) => setState(() => _grade = g)),
              ]),
              const SizedBox(height: AppSpacing.md),
              MoneyField(controller: _price, label: l.pricePaid, required: true, allowZero: false),
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: AppSpacing.sm, children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(label: Text(context.methodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
              ]),
              if (_cnicOn && ref.watch(permissionsProvider).viewCnic) ...[
                const Divider(height: AppSpacing.xl),
                Ltr(TextFormField(controller: _cnic, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.cnic))),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_front == null ? Icons.badge_outlined : Icons.check_circle_rounded),
                  title: Text(l.cnicFront),
                  onTap: () async {
                    final n = await _photo();
                    if (n != null) setState(() => _front = n);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_back == null ? Icons.badge_outlined : Icons.check_circle_rounded),
                  title: Text(l.cnicBack),
                  onTap: () async {
                    final n = await _photo();
                    if (n != null) setState(() => _back = n);
                  },
                ),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_a_photo_outlined),
                title: Text('${l.devicePhotos} (${_photos.length})'),
                onTap: () async {
                  final n = await _photo();
                  if (n != null) setState(() => _photos.add(n));
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: l.save, icon: Icons.check_rounded, loading: _busy, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail with seller receipt, CNIC view (logged, owner/manager only),
/// identity deletion and reversal.
class UsedPhoneDetailScreen extends ConsumerWidget {
  const UsedPhoneDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final db = ref.watch(databaseProvider);
    final can = ref.watch(permissionsProvider);
    return StreamBuilder<UsedPhonePurchase?>(
      stream: (db.select(db.usedPhonePurchases)..where((u) => u.id.equals(id))).watchSingleOrNull(),
      builder: (context, snap) {
        final u = snap.data;
        if (u == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final hasIdentity = u.sellerCnic != null || u.cnicFrontPath != null || u.cnicBackPath != null;
        return Scaffold(
          appBar: AppBar(title: Ltr(Text(u.docNo))),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              ListTile(title: Text(u.model), subtitle: Text('${Fmt.dateTime(u.date)} • ${gradeLabel(context, u.grade)}')),
              ListTile(title: Text(l.pricePaid), trailing: Ltr(Text(Fmt.money(u.price)))),
              PrimaryButton(
                label: l.sellerReceipt,
                icon: Icons.print_rounded,
                outlined: true,
                onPressed: () => guard(context, () async {
                  final pdf = await _sellerReceipt(ref, u);
                  await Printing.layoutPdf(onLayout: (_) async => pdf);
                }),
              ),
              if (hasIdentity && can.viewCnic) ...[
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: l.viewCnic,
                  icon: Icons.badge_outlined,
                  outlined: true,
                  onPressed: () async {
                    await ref.read(usedPhoneServiceProvider).logCnicView(u.id);
                    if (context.mounted) {
                      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _CnicView(doc: u)));
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: l.deleteIdentity,
                  icon: Icons.delete_forever_outlined,
                  outlined: true,
                  onPressed: () async {
                    final ok = await ConfirmSheet.show(context,
                        title: l.deleteIdentity, message: l.identityDeleted, confirmLabel: l.deleteIdentity, cancelLabel: l.cancel, destructive: true);
                    if (!ok || !context.mounted) return;
                    if (!await ref.read(pinGateProvider).requireOwner(context)) return;
                    await ref.read(usedPhoneServiceProvider).deleteIdentity(u.id, ref.read(photoVaultProvider).shred);
                    if (context.mounted) showMessage(context, l.identityDeleted);
                  },
                ),
              ],
              if (u.status == DocStatus.posted) ...[
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: l.reverse,
                  icon: Icons.undo_rounded,
                  outlined: true,
                  onPressed: () async {
                    if (!await ref.read(pinGateProvider).requireOwner(context) || !context.mounted) return;
                    final r = await guard(context, () => ref.read(usedPhoneServiceProvider).reverse(u.id));
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

  /// Simple purchase receipt for the seller to sign (spec 5.9). CNIC never
  /// appears in PDFs (spec 9).
  Future<Uint8List> _sellerReceipt(WidgetRef ref, UsedPhonePurchase u) async {
    final db = ref.read(databaseProvider);
    final k = await PdfKit.load();
    final b = ref.read(sessionProvider).business!;
    final seller = await (db.select(db.parties)..where((p) => p.id.equals(u.sellerPartyId))).getSingle();
    final unit = await (db.select(db.imeiUnits)..where((x) => x.id.equals(u.imeiUnitId))).getSingle();
    final doc = pw.Document(theme: k.theme());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        k.header(b, title: 'Used phone purchase receipt', subtitle: '${u.docNo} • ${Fmt.dateTime(u.date)}'),
        pw.SizedBox(height: 12),
        k.kv('Seller', seller.name),
        if (seller.phone != null) k.kv('Phone', seller.phone!),
        k.kv('Model', u.model),
        k.kv('IMEI', unit.imei1),
        if (unit.imei2 != null) k.kv('IMEI 2', unit.imei2!),
        k.kv('Condition', u.grade.name.toUpperCase()),
        k.kv('Price paid', PdfKit.money(u.price), strong: true, size: 12),
        pw.SizedBox(height: 16),
        pw.Text('I confirm I am the owner of this phone and have sold it to ${b.name} for the amount above.', style: k.small),
        pw.SizedBox(height: 40),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Seller signature: ____________', style: k.small),
          pw.Text('Shop: ____________', style: k.small),
        ]),
      ]),
    ));
    return doc.save();
  }
}

class _CnicView extends ConsumerWidget {
  const _CnicView({required this.doc});

  final UsedPhonePurchase doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final vault = ref.watch(photoVaultProvider);
    final photos = (jsonDecode(doc.devicePhotosJson) as List).cast<String>();
    return SecureArea(
      child: Scaffold(
        appBar: AppBar(title: Text(l.cnic)),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (doc.sellerCnic != null) Ltr(Text(doc.sellerCnic!, style: Theme.of(context).textTheme.headlineMedium)),
            for (final f in [doc.cnicFrontPath, doc.cnicBackPath, ...photos].whereType<String>())
              FutureBuilder<Uint8List?>(
                future: vault.read(f),
                builder: (context, s) => s.data == null
                    ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
                    : Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: Image.memory(s.data!)),
              ),
          ],
        ),
      ),
    );
  }
}
