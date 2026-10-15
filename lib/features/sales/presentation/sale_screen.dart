import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/accounting/posting.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/pin_gate.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/amount_keypad.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/labels.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/money_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/pro_gate.dart';
import '../../../core/widgets/scanner.dart';
import '../../parties/presentation/party_picker.dart';
import '../../products/data/products_repository.dart';
import '../application/cart.dart';
import '../application/sale_service.dart';

/// New Sale (POS) — the most important screen (spec 5.3).
///
/// Known item, cash sale: tap the product, tap Save. The Save button is
/// disabled while saving so a double tap can never create two invoices.
class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key});

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  List<SaleSearchHit>? _hits;
  bool _grid = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _runSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _search.text;
    final hits = await ref.read(productsRepoProvider).searchForSale(q, limit: 60);
    if (!mounted || q != _search.text) return;
    setState(() => _hits = hits);
    // A scanned/typed exact IMEI or barcode adds itself straight away.
    if (q.trim().isNotEmpty && hits.length == 1 && (hits.first.imeiUnit != null || _exactBarcode)) {
      _exactBarcode = false;
      await _add(hits.first);
      _search.clear();
      _runSearch();
    }
  }

  bool _exactBarcode = false;

  Future<void> _scan() async {
    final code = await scanCode(context);
    if (code == null) return;
    _exactBarcode = true;
    _search.text = code;
    await _runSearch();
  }

  Future<void> _add(SaleSearchHit hit) async {
    final cart = ref.read(cartProvider.notifier);
    if (hit.imeiUnit != null) {
      cart.add(
        productId: hit.product.id,
        variantId: hit.variant?.id,
        name: hit.label,
        price: hit.price,
        imeiUnitId: hit.imeiUnit!.id,
        imei: hit.imeiUnit!.imei1,
        stock: 1,
      );
    } else if (hit.product.tracksImei) {
      final unit = await _pickImei(hit);
      if (unit == null) return;
      cart.add(
          productId: hit.product.id,
          variantId: hit.variant?.id,
          name: hit.label,
          price: hit.price,
          imeiUnitId: unit.id,
          imei: unit.imei1,
          stock: 1);
    } else {
      cart.add(productId: hit.product.id, variantId: hit.variant?.id, name: hit.label, price: hit.price, stock: hit.qty);
    }
    HapticFeedback.selectionClick();
  }

  Future<ImeiUnit?> _pickImei(SaleSearchHit hit) async {
    final units = await ref.read(productsRepoProvider).inStockImeis(hit.product.id, variantId: hit.variant?.id);
    final inCart = ref.read(cartProvider).lines.map((l) => l.imeiUnitId).toSet();
    final free = units.where((u) => !inCart.contains(u.id)).toList();
    if (!mounted) return null;
    return showModalBottomSheet<ImeiUnit>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final l = ctx.l10n;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(l.pickImei, style: Theme.of(ctx).textTheme.titleLarge),
                  subtitle: Text(hit.label),
                  trailing: IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    onPressed: () async {
                      final code = await scanCode(ctx);
                      final match = free.where((u) => u.imei1 == code || u.imei2 == code).firstOrNull;
                      if (match != null && ctx.mounted) {
                        Navigator.pop(ctx, match);
                      } else if (code != null && ctx.mounted) {
                        showMessage(ctx, l.errImeiNotAvailable);
                      }
                    },
                  ),
                ),
                if (free.isEmpty) Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text(l.noImeiInStock)),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in free)
                        ListTile(
                          leading: const Icon(Icons.phone_android_rounded),
                          title: Ltr(Text(u.imei1)),
                          subtitle: u.imei2 == null ? null : Ltr(Text(u.imei2!)),
                          trailing: u.conditionGrade == null ? null : Text(u.conditionGrade!.name.toUpperCase()),
                          onTap: () => Navigator.pop(ctx, u),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _longPress(SaleSearchHit hit) async {
    if (hit.product.tracksImei) return _add(hit);
    final cart = ref.read(cartProvider.notifier);
    var line = ref.read(cartProvider).lines.where((l) => l.productId == hit.product.id && l.variantId == hit.variant?.id).firstOrNull;
    if (line == null) {
      cart.add(productId: hit.product.id, variantId: hit.variant?.id, name: hit.label, price: hit.price, stock: hit.qty);
      line = ref.read(cartProvider).lines.last;
    }
    if (mounted) await editCartLine(context, ref, line);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cart = ref.watch(cartProvider);
    final hits = _hits;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.newSale),
        actions: [
          IconButton(
            tooltip: _grid ? l.listView : l.gridView,
            icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: TextField(
              key: const Key('pos_search'),
              controller: _search,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.searchProducts,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  key: const Key('pos_scan'),
                  tooltip: l.scan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  onPressed: _scan,
                ),
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 150), _runSearch);
              },
              onSubmitted: (_) {
                _exactBarcode = true;
                _runSearch();
              },
            ),
          ),
          Expanded(
            child: hits == null
                ? const Center(child: CircularProgressIndicator())
                : hits.isEmpty
                    ? EmptyState(
                        icon: Icons.point_of_sale_rounded,
                        title: _search.text.isEmpty ? l.saleEmptyTitle : l.nothingFound,
                        message: _search.text.isEmpty ? l.saleEmptyBody : '',
                        actionLabel: _search.text.isEmpty && ref.watch(permissionsProvider).editProducts ? l.addProduct : null,
                        onAction: () => context.push(Routes.productNew).then((_) => _runSearch()),
                      )
                    : _grid
                        ? GridView.builder(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 120),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              mainAxisSpacing: AppSpacing.sm,
                              crossAxisSpacing: AppSpacing.sm,
                              mainAxisExtent: 168,
                            ),
                            itemCount: hits.length,
                            itemBuilder: (context, i) => _ProductCard(
                              hit: hits[i],
                              inCart: cart.lines.where((l) => l.productId == hits[i].product.id && l.variantId == hits[i].variant?.id).fold(0, (a, l) => a + l.unitQty),
                              onTap: () => _add(hits[i]),
                              onLongPress: () => _longPress(hits[i]),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: hits.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final h = hits[i];
                              return ListTile(
                                onTap: () => _add(h),
                                onLongPress: () => _longPress(h),
                                title: Text(h.label),
                                subtitle: Text(l.qtyLeft(Fmt.qty(h.qty))),
                                trailing: Ltr(Text(Fmt.money(h.price), style: Theme.of(context).textTheme.titleMedium)),
                              );
                            },
                          ),
          ),
        ],
      ),
      bottomSheet: cart.isEmpty ? null : const _CartBar(),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.hit, required this.inCart, required this.onTap, required this.onLongPress});

  final SaleSearchHit hit;
  final int inCart;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final out = hit.qty <= 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: inCart > 0 ? c.primaryContainer : null,
      child: InkWell(
        key: Key('pos_item_${hit.product.id}${hit.variant?.id ?? ''}'),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(hit.product.tracksImei ? Icons.phone_android_rounded : Icons.inventory_2_outlined, size: 18, color: c.primary),
                const Spacer(),
                if (inCart > 0)
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: c.primary,
                    child: Text('$inCart', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onPrimary)),
                  ),
              ]),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: Text(hit.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              ),
              Ltr(Text(Fmt.money(hit.price), style: theme.textTheme.titleMedium?.copyWith(color: c.primary))),
              Text(
                out ? context.l10n.soldOutWarn : context.l10n.qtyLeft(Fmt.qty(hit.qty)),
                style: theme.textTheme.labelSmall?.copyWith(color: out ? c.danger : c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom bar: total + one big Save button (saves with the chosen payment,
/// default Cash / walk-in). Tapping the total opens the cart sheet.
class _CartBar extends ConsumerWidget {
  const _CartBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final cart = ref.watch(cartProvider);
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const Key('cart_open'),
                  borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                  onTap: () => openCartSheet(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(l.itemsCount(cart.itemCount),
                                style: theme.textTheme.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const Icon(Icons.expand_less_rounded, size: 18),
                        ]),
                        Text(
                          '${_modeLabel(context, cart.mode)}${cart.partyName != null ? ' • ${cart.partyName}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const SizedBox(width: 190, child: SaveSaleButton()),
            ],
          ),
        ),
      ),
    );
  }
}

String _modeLabel(BuildContext context, SalePaymentMode m) {
  final l = context.l10n;
  return switch (m) {
    SalePaymentMode.cash => l.payCash,
    SalePaymentMode.udhaar => l.payUdhaar,
    SalePaymentMode.mixed => l.payMixed,
    SalePaymentMode.wallet => l.payWallet,
    SalePaymentMode.qist => l.payQist,
  };
}

/// Guards against double taps for the whole app (one sale at a time).
final ValueNotifier<bool> _saving = ValueNotifier(false);

class SaveSaleButton extends ConsumerWidget {
  const SaveSaleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: _saving,
      builder: (context, saving, _) => PrimaryButton(
        key: const Key('save_sale'),
        label: context.l10n.saveSaleAmount(Fmt.money(cart.grandTotal)),
        icon: Icons.check_rounded,
        loading: saving,
        onPressed: cart.isEmpty ? null : () => saveCart(context, ref),
      ),
    );
  }
}

/// Validates and saves the cart as ONE posting transaction, then opens the
/// success screen.
Future<void> saveCart(BuildContext context, WidgetRef ref) async {
  if (_saving.value) return;
  final l = context.l10n;
  final cart = ref.read(cartProvider);
  if (cart.isEmpty) return;
  final needsParty = cart.mode == SalePaymentMode.udhaar || cart.mode == SalePaymentMode.mixed || cart.mode == SalePaymentMode.qist;
  if (needsParty && cart.partyId == null) {
    showMessage(context, l.errPartyRequired);
    final p = await pickParty(context, allowWalkIn: false);
    if (p?.id == null) return;
    ref.read(cartProvider.notifier).setParty(p!.id, p.name);
    if (!context.mounted) return;
  }
  _saving.value = true;
  try {
    final current = ref.read(cartProvider);
    final due = switch (current.mode) {
      SalePaymentMode.udhaar => current.grandTotal,
      SalePaymentMode.mixed => current.grandTotal - current.paidNow,
      SalePaymentMode.qist => current.grandTotal - (current.qist?.downPayment ?? Money.zero),
      _ => Money.zero,
    };
    if (current.partyId != null && due.isPositive) {
      final over = await ref.read(partyServiceProvider).exceedsCreditLimit(current.partyId!, due);
      if (over && context.mounted) {
        final party = await ref.read(partiesRepoProvider).party(current.partyId!);
        if (!context.mounted) return;
        final go = await ConfirmSheet.show(context,
            title: l.creditLimit,
            message: l.creditLimitWarning(party?.name ?? '', Fmt.money(party?.creditLimit ?? Money.zero)),
            confirmLabel: l.continueAnyway,
            cancelLabel: l.cancel);
        if (!go) return;
      }
    }
    final svc = ref.read(saleServiceProvider);
    SaleResult? result;
    try {
      result = await svc.createSale(current.toInput());
    } on PostingException catch (e) {
      if (e.code != PostingError.belowMinPrice || !context.mounted) rethrow;
      if (!await ref.read(pinGateProvider).requireOwner(context, reason: l.belowMinPriceAsk)) return;
      result = await svc.createSale(current.toInput(priceOverrideApproved: true));
    }
    savedHaptic();
    ref.read(cartProvider.notifier).clear();
    if (context.mounted) {
      if (Navigator.of(context).canPop()) Navigator.of(context).popUntil((r) => r is! ModalBottomSheetRoute);
      context.push(Routes.saleDone(result.saleId));
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  } finally {
    _saving.value = false;
  }
}

/// Opens the cart sheet: items, steppers, line discount, customer,
/// payment and totals (spec 5.3 steps 4–6).
Future<void> openCartSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.92, child: _CartSheet()),
    );

final _taxEnabledProvider = FutureProvider.autoDispose<bool>((ref) => ref.watch(settingsRepoProvider).getBool(SettingKeys.taxEnabled));

class _CartSheet extends ConsumerStatefulWidget {
  const _CartSheet();

  @override
  ConsumerState<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<_CartSheet> {
  final _markup = TextEditingController();
  final _down = TextEditingController();
  final _count = TextEditingController(text: '6');
  final _gName = TextEditingController();
  final _gPhone = TextEditingController();
  QistFrequency _freq = QistFrequency.monthly;

  @override
  void dispose() {
    for (final c in [_markup, _down, _count, _gName, _gPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncQist() {
    ref.read(cartProvider.notifier).setQist(QistInput(
          markup: MoneyField.read(_markup) ?? Money.zero,
          downPayment: MoneyField.read(_down) ?? Money.zero,
          installments: int.tryParse(_count.text) ?? 1,
          frequency: _freq,
          guarantorName: _gName.text.trim().isEmpty ? null : _gName.text.trim(),
          guarantorPhone: _gPhone.text.trim().isEmpty ? null : _gPhone.text.trim(),
        ));
  }

  Future<void> _setMode(SalePaymentMode m) async {
    if (m == SalePaymentMode.qist && !await requirePro(context, ref)) return;
    final n = ref.read(cartProvider.notifier);
    n.setMode(m);
    if (m == SalePaymentMode.wallet && ref.read(cartProvider).method == PaymentMethod.cash) n.setMethod(PaymentMethod.jazzcash);
    if (m == SalePaymentMode.qist) _syncQist();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);
    final n = ref.read(cartProvider.notifier);
    final t = cart.totals;
    final taxOn = ref.watch(_taxEnabledProvider).value ?? false;

    Future<Money?> keypad(String title, Money initial) =>
        AmountKeypad.show(context, title: title, doneLabel: l.done, initial: initial);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            children: [
              Text(l.cart, style: theme.textTheme.titleLarge),
              if (cart.isEmpty) Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text(l.cartEmpty)),
              for (final line in cart.lines)
                _CartLineTile(
                  line: line,
                  onMinus: () => n.setQty(line.key, line.unitQty - 1),
                  onPlus: () => n.setQty(line.key, line.unitQty + 1),
                  onTap: () => editCartLine(context, ref, line),
                ),
              const Divider(),
              ListTile(
                key: const Key('cart_customer'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(cart.partyName ?? l.walkInCustomer),
                subtitle: Text(l.customer),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final p = await pickParty(context);
                  if (p != null) n.setParty(p.id, p.name);
                },
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final m in SalePaymentMode.values)
                    ChoiceChip(
                      key: Key('mode_${m.name}'),
                      label: Text(_modeLabel(context, m)),
                      selected: cart.mode == m,
                      onSelected: (_) => _setMode(m),
                    ),
                ],
              ),
              if (cart.mode == SalePaymentMode.wallet || cart.mode == SalePaymentMode.mixed) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(spacing: AppSpacing.sm, children: [
                  for (final m in PaymentMethod.values)
                    if (cart.mode == SalePaymentMode.mixed || m != PaymentMethod.cash)
                      ChoiceChip(
                        label: Text(context.methodLabel(m)),
                        selected: cart.method == m,
                        onSelected: (_) => n.setMethod(m),
                      ),
                ]),
              ],
              if (cart.mode == SalePaymentMode.mixed) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  Expanded(
                    child: _AmountTile(
                      key: const Key('mixed_paid'),
                      label: l.paidNow,
                      value: cart.paidNow,
                      onTap: () async {
                        final m = await keypad(l.paidNow, cart.paidNow);
                        if (m != null) n.setPaidNow(m);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _AmountTile(label: l.udhaarPart, value: cart.grandTotal - cart.paidNow, color: c.danger)),
                ]),
              ],
              if (cart.mode == SalePaymentMode.qist) ...[
                const SizedBox(height: AppSpacing.md),
                Text(l.qistTerms, style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  Expanded(child: MoneyField(controller: _markup, label: l.markup, onChanged: (_) => _syncQist())),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: MoneyField(controller: _down, label: l.downPayment, onChanged: (_) => _syncQist())),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  Expanded(child: IntField(controller: _count, label: l.installments, min: 1, onChanged: (_) => _syncQist())),
                  const SizedBox(width: AppSpacing.sm),
                  SegmentedButton<QistFrequency>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: QistFrequency.weekly, label: Text(l.weekly)),
                      ButtonSegment(value: QistFrequency.monthly, label: Text(l.monthly)),
                    ],
                    selected: {_freq},
                    onSelectionChanged: (s) {
                      setState(() => _freq = s.first);
                      _syncQist();
                    },
                  ),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  Expanded(child: TextField(controller: _gName, decoration: InputDecoration(labelText: l.guarantorName), onChanged: (_) => _syncQist())),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _gPhone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: l.guarantorPhone),
                      onChanged: (_) => _syncQist(),
                    ),
                  ),
                ]),
                if (cart.qist != null && cart.qist!.installments > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(l.perInstallment(Fmt.money(
                        (cart.grandTotal - cart.qist!.downPayment).ratio(1, cart.qist!.installments)))),
                  ),
              ],
              const Divider(height: AppSpacing.lg),
              Row(children: [
                Expanded(
                  child: _AmountTile(
                    label: l.invoiceDiscount,
                    value: cart.discount,
                    onTap: () async {
                      final m = await keypad(l.invoiceDiscount, cart.discount);
                      if (m != null) n.setDiscount(m);
                    },
                  ),
                ),
                if (cart.mode != SalePaymentMode.qist) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _AmountTile(
                      label: l.delivery,
                      value: cart.delivery,
                      onTap: () async {
                        final m = await keypad(l.delivery, cart.delivery);
                        if (m != null) n.setDelivery(m);
                      },
                    ),
                  ),
                  if (taxOn) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _AmountTile(
                        label: l.tax,
                        value: cart.tax,
                        onTap: () async {
                          final m = await keypad(l.tax, cart.tax);
                          if (m != null) n.setTax(m);
                        },
                      ),
                    ),
                  ],
                ],
              ]),
              const SizedBox(height: AppSpacing.md),
              _TotalRow(label: l.subtotal, value: t.subtotal),
              if (!cart.discount.isZero) _TotalRow(label: l.discount, value: -cart.discount),
              if (!cart.delivery.isZero) _TotalRow(label: l.delivery, value: cart.delivery),
              if (!cart.tax.isZero) _TotalRow(label: l.tax, value: cart.tax),
              if (cart.mode == SalePaymentMode.qist && cart.qist != null) _TotalRow(label: l.markup, value: cart.qist!.markup),
              _TotalRow(label: cart.mode == SalePaymentMode.qist ? l.qistTotal : l.total, value: cart.grandTotal, big: true),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom),
          child: const SaveSaleButton(),
        ),
      ],
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.line, required this.onMinus, required this.onPlus, required this.onTap});

  final CartLine line;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Ltr(Text(
                    [
                      '${Fmt.money(line.unitPrice)}${line.unitSymbol != null ? ' / ${line.unitSymbol}' : ''}',
                      if (!line.discount.isZero) '− ${Fmt.money(line.discount)}',
                      if (line.imei != null) 'IMEI ${line.imei}',
                    ].join('  '),
                    style: theme.textTheme.bodySmall,
                  )),
                  if (!line.isImei && line.unitQty * line.factor > line.stock)
                    Text(context.l10n.errStock, style: theme.textTheme.labelSmall?.copyWith(color: c.warning)),
                ],
              ),
            ),
            if (!line.isImei) ...[
              IconButton(onPressed: onMinus, icon: const Icon(Icons.remove_circle_outline_rounded), tooltip: '-'),
              Ltr(Text('${line.unitQty}', style: theme.textTheme.titleMedium)),
              IconButton(onPressed: onPlus, icon: const Icon(Icons.add_circle_outline_rounded), tooltip: '+'),
            ] else
              IconButton(onPressed: onMinus, icon: const Icon(Icons.delete_outline_rounded)),
            SizedBox(
              width: 88,
              child: Ltr(Text(Fmt.money(line.total), textAlign: TextAlign.end, style: theme.textTheme.titleSmall)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({super.key, required this.label, required this.value, this.onTap, this.color});

  final String label;
  final Money value;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.background,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              Ltr(Text(Fmt.money(value), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color))),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.big = false});

  final String label;
  final Money value;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final style = big ? Theme.of(context).textTheme.headlineMedium : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Ltr(Text(Fmt.money(value), style: style)),
      ]),
    );
  }
}

/// Long-press / tap editor: quantity, unit (e.g. carton), price, discount.
Future<void> editCartLine(BuildContext context, WidgetRef ref, CartLine line) async {
  final l = context.l10n;
  final product = await ref.read(productsRepoProvider).product(line.productId);
  final units = await ref.read(productsRepoProvider).units();
  if (!context.mounted || product == null) return;
  final alt = product.altUnitId == null ? null : units.where((u) => u.id == product.altUnitId).firstOrNull;
  final base = units.where((u) => u.id == product.unitId).firstOrNull;
  final qty = TextEditingController(text: '${line.unitQty}');
  final price = TextEditingController(text: MoneyField.text(line.unitPrice));
  final disc = TextEditingController(text: MoneyField.text(line.discount));
  var useAlt = line.unitId != null && line.unitId == alt?.id;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(line.name, style: Theme.of(ctx).textTheme.titleLarge),
              Text(l.editLine),
              const SizedBox(height: AppSpacing.md),
              if (alt != null && !line.isImei)
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(base?.symbol ?? l.pcs)),
                    ButtonSegment(value: true, label: Text('${alt.symbol} (${alt.factor})')),
                  ],
                  selected: {useAlt},
                  onSelectionChanged: (s) => set(() {
                    useAlt = s.first;
                    price.text = MoneyField.text(useAlt ? product.salePrice.times(alt.factor) : product.salePrice);
                  }),
                ),
              const SizedBox(height: AppSpacing.sm),
              if (!line.isImei) IntField(controller: qty, label: l.quantity, min: 1),
              const SizedBox(height: AppSpacing.sm),
              MoneyField(controller: price, label: l.price),
              const SizedBox(height: AppSpacing.sm),
              MoneyField(controller: disc, label: l.lineDiscount),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                Expanded(
                  child: PrimaryButton(
                    label: l.remove,
                    outlined: true,
                    icon: Icons.delete_outline_rounded,
                    onPressed: () {
                      ref.read(cartProvider.notifier).remove(line.key);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: l.done,
                    icon: Icons.check_rounded,
                    onPressed: () {
                      final q = int.tryParse(qty.text) ?? line.unitQty;
                      final p = MoneyField.read(price) ?? line.unitPrice;
                      final d = MoneyField.read(disc) ?? Money.zero;
                      if (q <= 0 || d > p.times(q)) {
                        showMessage(ctx, l.invalidNumber);
                        return;
                      }
                      ref.read(cartProvider.notifier).update(
                            line.key,
                            (x) => x.copyWith(
                              unitQty: line.isImei ? 1 : q,
                              unitPrice: p,
                              discount: d,
                              unitId: useAlt ? alt!.id : product.unitId,
                              unitSymbol: useAlt ? alt!.symbol : base?.symbol,
                              factor: useAlt ? alt!.factor : 1,
                            ),
                          );
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}
