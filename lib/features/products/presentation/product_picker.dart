import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/scanner.dart';
import '../data/products_repository.dart';

/// Search-and-pick a product (and variant) by name, SKU, barcode or IMEI.
Future<SaleSearchHit?> pickProduct(BuildContext context, {bool imeiOnly = false, bool excludeImei = false}) =>
    showModalBottomSheet<SaleSearchHit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _Picker(imeiOnly: imeiOnly, excludeImei: excludeImei)),
    );

class _Picker extends ConsumerStatefulWidget {
  const _Picker({required this.imeiOnly, required this.excludeImei});

  final bool imeiOnly;
  final bool excludeImei;

  @override
  ConsumerState<_Picker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_Picker> {
  final _q = TextEditingController();
  List<SaleSearchHit> _hits = const [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final hits = await ref.read(productsRepoProvider).searchForSale(_q.text, limit: 60);
    if (!mounted) return;
    setState(() => _hits = hits
        .where((h) => (!widget.imeiOnly || h.product.tracksImei) && (!widget.excludeImei || !h.product.tracksImei))
        .toList());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        child: TextField(
          controller: _q,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l.searchProducts,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: () async {
                final c = await scanCode(context);
                if (c != null) {
                  _q.text = c;
                  _run();
                }
              },
            ),
          ),
          onChanged: (_) => _run(),
        ),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: _hits.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final h = _hits[i];
            return ListTile(
              title: Text(h.label),
              subtitle: Text(l.qtyLeft(Fmt.qty(h.qty))),
              trailing: Ltr(Text(Fmt.money(h.price))),
              onTap: () => Navigator.pop(context, h),
            );
          },
        ),
      ),
    ]);
  }
}
