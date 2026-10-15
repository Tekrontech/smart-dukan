import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/labels.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/money_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/scanner.dart';
import '../../parties/presentation/party_picker.dart';
import '../../products/application/product_service.dart';
import '../../products/presentation/product_picker.dart';
import '../application/purchase_service.dart';

class _Line {
  _Line({required this.product, this.variantId, required this.label, required Money cost, this.altUnit})
      : cost = TextEditingController(text: MoneyField.text(cost)),
        qty = TextEditingController(text: '1');

  final Product product;
  final String? variantId;
  final String label;
  final UnitRow? altUnit;
  final TextEditingController cost;
  final TextEditingController qty;
  bool useAlt = false;
  final List<TextEditingController> imeis = [];

  int get unitQty => int.tryParse(qty.text) ?? 0;
  Money get unitCost => MoneyField.read(cost) ?? Money.zero;
  Money get total => unitCost.times(unitQty);

  void dispose() {
    cost.dispose();
    qty.dispose();
    for (final c in imeis) {
      c.dispose();
    }
  }
}

/// Purchase from a supplier (spec 5.4): items with cost, paid amount, due,
/// optional bill photo. Updates stock and weighted average cost.
class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  final List<_Line> _lines = [];
  final _discount = TextEditingController();
  final _extra = TextEditingController();
  final _paid = TextEditingController();
  final _billNo = TextEditingController();
  String? _partyId;
  String? _partyName;
  PaymentMethod _method = PaymentMethod.cash;
  String? _photo;
  bool _paidTouched = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    for (final c in [_discount, _extra, _paid, _billNo]) {
      c.dispose();
    }
    super.dispose();
  }

  Money get _subtotal => Money.sum(_lines.map((l) => l.total));
  Money get _total => _subtotal - (MoneyField.read(_discount) ?? Money.zero) + (MoneyField.read(_extra) ?? Money.zero);

  void _recalc() {
    if (!_paidTouched) _paid.text = MoneyField.text(_total);
    setState(() {});
  }

  Future<void> _addItem() async {
    final hit = await pickProduct(context);
    if (hit == null) return;
    final units = await ref.read(productsRepoProvider).units();
    final alt = hit.product.altUnitId == null ? null : units.where((u) => u.id == hit.product.altUnitId).firstOrNull;
    final line = _Line(
      product: hit.product,
      variantId: hit.variant?.id,
      label: hit.label,
      cost: hit.variant?.avgCost ?? hit.product.avgCost,
      altUnit: alt,
    );
    if (hit.product.tracksImei) line.imeis.add(TextEditingController());
    setState(() => _lines.add(line));
    _recalc();
  }

  void _syncImeiFields(_Line l) {
    final want = l.unitQty.clamp(0, 50);
    while (l.imeis.length < want) {
      l.imeis.add(TextEditingController());
    }
    while (l.imeis.length > want) {
      l.imeis.removeLast().dispose();
    }
  }

  Future<void> _save() async {
    if (_lines.isEmpty) return;
    final input = PurchaseInput(
      partyId: _partyId,
      lines: [
        for (final l in _lines)
          PurchaseLineInput(
            productId: l.product.id,
            variantId: l.variantId,
            unitId: l.useAlt ? l.altUnit!.id : l.product.unitId,
            unitQty: l.unitQty,
            unitCost: l.unitCost,
            imeis: [for (final c in l.imeis) if (c.text.trim().isNotEmpty) ImeiInput(imei1: c.text.trim())],
          ),
      ],
      discount: MoneyField.read(_discount) ?? Money.zero,
      extraCost: MoneyField.read(_extra) ?? Money.zero,
      paid: MoneyField.read(_paid) ?? Money.zero,
      method: _method,
      supplierBillNo: _billNo.text.trim().isEmpty ? null : _billNo.text.trim(),
      billPhotoPath: _photo,
    );
    setState(() => _busy = true);
    final r = await guard(context, () => ref.read(purchaseServiceProvider).createPurchase(input));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      savedHaptic();
      showMessage(context, context.l10n.purchaseSaved);
      context.pushReplacement(Routes.purchaseDetail(r.purchaseId));
    }
  }

  Future<void> _takePhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 70);
    if (x == null) return;
    final name = await ref.read(photoVaultProvider).save(await x.readAsBytes());
    setState(() => _photo = name);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final due = _total - (MoneyField.read(_paid) ?? Money.zero);
    return Scaffold(
      appBar: AppBar(title: Text(l.newPurchase)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(_partyName ?? l.noSupplier),
              subtitle: Text(l.supplier),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final p = await pickParty(context, kind: PartyType.supplier);
                if (p != null) {
                  setState(() {
                    _partyId = p.id;
                    _partyName = p.name;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final line in _lines) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm + 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(line.label, style: theme.textTheme.titleSmall)),
                    IconButton(
                      onPressed: () => setState(() {
                        _lines.remove(line);
                        line.dispose();
                        _recalc();
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                  Row(children: [
                    Expanded(
                      child: IntField(
                        controller: line.qty,
                        label: l.quantity,
                        min: 1,
                        onChanged: (_) {
                          if (line.product.tracksImei) _syncImeiFields(line);
                          _recalc();
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: MoneyField(controller: line.cost, label: l.unitCost, onChanged: (_) => _recalc())),
                  ]),
                  if (line.altUnit != null && !line.product.tracksImei)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${line.altUnit!.name} (${line.altUnit!.factor})'),
                      value: line.useAlt,
                      onChanged: (v) => setState(() => line.useAlt = v),
                    ),
                  if (line.product.tracksImei)
                    for (final c in line.imeis)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Ltr(TextField(
                          controller: c,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l.imei1,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              onPressed: () async {
                                final code = await scanCode(context);
                                if (code != null) c.text = code;
                              },
                            ),
                          ),
                        )),
                      ),
                  Align(alignment: AlignmentDirectional.centerEnd, child: Ltr(Text(Fmt.money(line.total)))),
                ]),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          OutlinedButton.icon(onPressed: _addItem, icon: const Icon(Icons.add), label: Text(l.addItem)),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: MoneyField(controller: _discount, label: l.discount, onChanged: (_) => _recalc())),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: MoneyField(controller: _extra, label: l.extraCost, onChanged: (_) => _recalc())),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(
              child: MoneyField(
                controller: _paid,
                label: l.paidToSupplier,
                onChanged: (_) {
                  _paidTouched = true;
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(labelText: l.duePart),
                child: Ltr(Text(Fmt.money(due))),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, children: [
            for (final m in PaymentMethod.values)
              ChoiceChip(label: Text(context.methodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
          ]),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _billNo, decoration: InputDecoration(labelText: l.supplierBillNo)),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_photo == null ? Icons.add_a_photo_outlined : Icons.check_circle_rounded),
            title: Text(l.billPhoto),
            onTap: _takePhoto,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: Text(l.total, style: theme.textTheme.titleLarge)),
            Ltr(Text(Fmt.money(_total), style: theme.textTheme.titleLarge)),
          ]),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: l.save, icon: Icons.check_rounded, loading: _busy, onPressed: _lines.isEmpty ? null : _save),
        ],
      ),
    );
  }
}
