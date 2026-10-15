import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/money_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/scanner.dart';
import '../application/product_service.dart';

/// Product form (spec 5.5): name, category, brand, SKU (auto), barcodes,
/// unit, prices, min stock alert, IMEI flag, variants, opening stock.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});

  final String? productId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _nameUr = TextEditingController();
  final _sku = TextEditingController();
  final _price = TextEditingController();
  final _minPrice = TextEditingController();
  final _cost = TextEditingController();
  final _minStock = TextEditingController();
  final _qty = TextEditingController();
  final _warranty = TextEditingController();
  final List<String> _barcodes = [];
  final List<({TextEditingController label, TextEditingController price})> _variants = [];
  final List<({TextEditingController imei1, TextEditingController imei2})> _imeis = [];
  String? _categoryId;
  String? _brandId;
  String? _unitId;
  String? _altUnitId;
  bool _tracksImei = false;
  bool _saving = false;
  bool _loaded = false;
  Product? _existing;

  bool get _editing => widget.productId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(productsRepoProvider);
    final units = await repo.units();
    if (_editing) {
      final p = await repo.product(widget.productId!);
      if (p != null) {
        _existing = p;
        _name.text = p.name;
        _nameUr.text = p.nameUr ?? '';
        _sku.text = p.sku;
        _price.text = MoneyField.text(p.salePrice);
        _minPrice.text = MoneyField.text(p.minSalePrice);
        _minStock.text = p.minStock == 0 ? '' : '${p.minStock}';
        _warranty.text = p.warrantyDays == 0 ? '' : '${p.warrantyDays}';
        _categoryId = p.categoryId;
        _brandId = p.brandId;
        _unitId = p.unitId;
        _altUnitId = p.altUnitId;
        _tracksImei = p.tracksImei;
        final codes = await (ref.read(databaseProvider).select(ref.read(databaseProvider).barcodes)
              ..where((b) => b.productId.equals(p.id)))
            .get();
        _barcodes.addAll(codes.map((b) => b.code));
      }
    } else {
      _unitId = units.where((u) => u.symbol == 'pcs').firstOrNull?.id;
      _imeis.add((imei1: TextEditingController(), imei2: TextEditingController()));
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [_name, _nameUr, _sku, _price, _minPrice, _cost, _minStock, _qty, _warranty]) {
      c.dispose();
    }
    for (final v in _variants) {
      v.label.dispose();
      v.price.dispose();
    }
    for (final i in _imeis) {
      i.imei1.dispose();
      i.imei2.dispose();
    }
    super.dispose();
  }

  Future<String?> _askName(String title) async {
    final c = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(context.l10n.add)),
        ],
      ),
    );
    return res == null || res.isEmpty ? null : res;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final input = ProductInput(
      name: _name.text,
      nameUr: _nameUr.text.trim().isEmpty ? null : _nameUr.text.trim(),
      sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      categoryId: _categoryId,
      brandId: _brandId,
      unitId: _unitId,
      altUnitId: _altUnitId,
      salePrice: MoneyField.read(_price)!,
      minSalePrice: MoneyField.read(_minPrice) ?? Money.zero,
      minStock: IntField.read(_minStock),
      tracksImei: _tracksImei,
      warrantyDays: IntField.read(_warranty),
      barcodes: _barcodes,
    );
    setState(() => _saving = true);
    final svc = ref.read(productServiceProvider);
    final ok = await guard(context, () async {
      if (_editing) {
        await svc.updateProduct(widget.productId!, input);
      } else {
        final cost = MoneyField.read(_cost) ?? Money.zero;
        await svc.createProduct(
          input,
          openingQty: _tracksImei ? 0 : IntField.read(_qty),
          openingCost: cost,
          openingImeis: _tracksImei
              ? [
                  for (final i in _imeis)
                    if (i.imei1.text.trim().isNotEmpty)
                      ImeiInput(imei1: i.imei1.text.trim(), imei2: i.imei2.text.trim(), cost: cost),
                ]
              : const [],
          variants: [
            for (final v in _variants)
              if (v.label.text.trim().isNotEmpty)
                (label: v.label.text.trim(), salePrice: MoneyField.read(v.price) ?? input.salePrice, sku: null),
          ],
        );
      }
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) {
      showMessage(context, context.l10n.productSaved);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final repo = ref.watch(productsRepoProvider);
    final svc = ref.read(productServiceProvider);
    final showCost = ref.watch(permissionsProvider).seeCost;
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? l.editProduct : l.addProduct)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            TextFormField(
              key: const Key('product_name'),
              controller: _name,
              autofocus: !_editing,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.productName),
              validator: (v) => (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _nameUr, decoration: InputDecoration(labelText: '${l.productNameUr} (${l.optional})')),
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Expanded(
                child: MoneyField(key: const Key('product_price'), controller: _price, label: l.salePrice, required: true),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: MoneyField(controller: _minPrice, label: l.minSalePrice)),
            ]),
            const SizedBox(height: AppSpacing.md),
            StreamBuilder<List<Category>>(
              stream: repo.watchCategories(),
              builder: (context, snap) => _PickerRow(
                label: l.category,
                value: _categoryId,
                items: {for (final c in snap.data ?? const <Category>[]) c.id: c.name},
                onChanged: (v) => setState(() => _categoryId = v),
                onAdd: () async {
                  final name = await _askName(l.newCategory);
                  if (name == null) return;
                  final id = await svc.createCategory(name);
                  setState(() => _categoryId = id);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            StreamBuilder<List<Brand>>(
              stream: repo.watchBrands(),
              builder: (context, snap) => _PickerRow(
                label: l.brand,
                value: _brandId,
                items: {for (final b in snap.data ?? const <Brand>[]) b.id: b.name},
                onChanged: (v) => setState(() => _brandId = v),
                onAdd: () async {
                  final name = await _askName(l.newBrand);
                  if (name == null) return;
                  final id = await svc.createBrand(name);
                  setState(() => _brandId = id);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Ltr(TextFormField(controller: _sku, decoration: InputDecoration(labelText: l.skuAuto))),
            const SizedBox(height: AppSpacing.md),
            StreamBuilder<List<UnitRow>>(
              stream: repo.watchUnits(),
              builder: (context, snap) {
                final units = snap.data ?? const <UnitRow>[];
                final base = units.where((u) => u.baseUnitId == null).toList();
                final bigger = units.where((u) => u.baseUnitId != null && u.baseUnitId == _unitId).toList();
                return Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: base.any((u) => u.id == _unitId) ? _unitId : null,
                      decoration: InputDecoration(labelText: l.unit),
                      items: [for (final u in base) DropdownMenuItem(value: u.id, child: Text('${u.name} (${u.symbol})'))],
                      onChanged: _editing
                          ? null
                          : (v) => setState(() {
                                _unitId = v;
                                _altUnitId = null;
                              }),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: bigger.any((u) => u.id == _altUnitId) ? _altUnitId : null,
                      decoration: InputDecoration(labelText: l.bigUnit),
                      items: [
                        DropdownMenuItem(value: null, child: Text(l.none)),
                        for (final u in bigger) DropdownMenuItem(value: u.id, child: Text('${u.name} = ${u.factor}')),
                      ],
                      onChanged: (v) => setState(() => _altUnitId = v),
                    ),
                  ),
                ]);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Expanded(child: IntField(controller: _minStock, label: l.minStockAlert)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: IntField(controller: _warranty, label: l.warrantyDays)),
            ]),
            const SizedBox(height: AppSpacing.md),
            Text(l.barcodes, style: theme.textTheme.titleSmall),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final b in _barcodes)
                  InputChip(label: Ltr(Text(b)), onDeleted: _editing ? null : () => setState(() => _barcodes.remove(b))),
                ActionChip(
                  avatar: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text(l.addBarcode),
                  onPressed: () async {
                    final code = await scanCode(context);
                    if (code != null && !_barcodes.contains(code)) setState(() => _barcodes.add(code));
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.tracksImei),
              secondary: const Icon(Icons.phone_android_rounded),
              value: _tracksImei,
              onChanged: _editing ? null : (v) => setState(() => _tracksImei = v),
            ),
            if (!_editing) ...[
              const Divider(),
              Text(l.variants, style: theme.textTheme.titleSmall),
              for (var i = 0; i < _variants.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Row(children: [
                    Expanded(flex: 3, child: TextField(controller: _variants[i].label, decoration: InputDecoration(labelText: l.variantLabel))),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(flex: 2, child: MoneyField(controller: _variants[i].price, label: l.salePrice)),
                    IconButton(onPressed: () => setState(() => _variants.removeAt(i)), icon: const Icon(Icons.close)),
                  ]),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _variants.add((label: TextEditingController(), price: TextEditingController()))),
                  icon: const Icon(Icons.add),
                  label: Text(l.addVariant),
                ),
              ),
              const Divider(),
              Text(l.openingStock, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              if (showCost) MoneyField(controller: _cost, label: l.openingCost),
              const SizedBox(height: AppSpacing.sm),
              if (!_tracksImei)
                IntField(key: const Key('opening_qty'), controller: _qty, label: l.openingQty)
              else ...[
                for (var i = 0; i < _imeis.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(children: [
                      Expanded(
                        child: Ltr(TextField(
                          controller: _imeis[i].imei1,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l.imei1,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              onPressed: () async {
                                final code = await scanCode(context);
                                if (code != null) _imeis[i].imei1.text = code;
                              },
                            ),
                          ),
                        )),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Ltr(TextField(
                          controller: _imeis[i].imei2,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: l.imei2),
                        )),
                      ),
                    ]),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _imeis.add((imei1: TextEditingController(), imei2: TextEditingController()))),
                    icon: const Icon(Icons.add),
                    label: Text(l.addImei),
                  ),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(key: const Key('product_save'), label: l.save, icon: Icons.check_rounded, loading: _saving, onPressed: _save),
            if (_editing && _existing != null && ref.watch(permissionsProvider).deleteMasters) ...[
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: l.deactivate,
                icon: Icons.visibility_off_outlined,
                outlined: true,
                onPressed: () async {
                  await guard(context, () => svc.setActive(_existing!.id, false));
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({required this.label, required this.value, required this.items, required this.onChanged, required this.onAdd});

  final String label;
  final String? value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: DropdownButtonFormField<String?>(
          key: ValueKey('$label:$value:${items.length}'),
          isExpanded: true,
          initialValue: items.containsKey(value) ? value : null,
          decoration: InputDecoration(labelText: label),
          items: [
            DropdownMenuItem(value: null, child: Text(context.l10n.none)),
            for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: onChanged,
        ),
      ),
      IconButton(onPressed: onAdd, icon: const Icon(Icons.add_circle_outline_rounded), tooltip: context.l10n.add),
    ]);
  }
}
