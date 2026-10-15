import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/scanner.dart';
import '../data/products_repository.dart';

/// Stock tab (spec 5.5): search, filters, paged list.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  final _search = TextEditingController();
  StockFilter _filter = StockFilter.all;
  String? _category;
  int _limit = ProductsRepository.pageSize;
  Stream<List<ProductListItem>>? _stream;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _stream = ref
          .read(productsRepoProvider)
          .list(search: _search.text, filter: _filter, categoryId: _category, limit: _limit)
          .watch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final can = ref.watch(permissionsProvider);
    final categories = ref.watch(_categoriesProvider).value ?? const <Category>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(l.tabStock),
        actions: [
          if (can.editProducts)
            IconButton(
              tooltip: l.importProducts,
              icon: const Icon(Icons.upload_file_rounded),
              onPressed: () => context.push(Routes.productImport),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: l.searchProducts,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: l.scan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  onPressed: () async {
                    final code = await scanCode(context);
                    if (code != null) {
                      _search.text = code;
                      _reload();
                    }
                  },
                ),
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 200), _reload);
              },
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                for (final f in StockFilter.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(switch (f) {
                        StockFilter.all => l.filterAll,
                        StockFilter.low => l.filterLow,
                        StockFilter.out => l.filterOut,
                        StockFilter.imei => l.filterImei,
                      }),
                      selected: _filter == f,
                      onSelected: (_) {
                        _filter = f;
                        _reload();
                      },
                    ),
                  ),
                if (categories.isNotEmpty)
                  DropdownButton<String?>(
                    value: _category,
                    hint: Text(l.allCategories),
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(value: null, child: Text(l.allCategories)),
                      for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) {
                      _category = v;
                      _reload();
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ProductListItem>>(
              stream: _stream,
              builder: (context, snap) {
                final items = snap.data;
                if (items == null) return const Center(child: CircularProgressIndicator());
                if (items.isEmpty) {
                  final searching = _search.text.isNotEmpty || _filter != StockFilter.all || _category != null;
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: searching ? l.nothingFound : l.stockEmptyTitle,
                    message: searching ? '' : l.stockEmptyBody,
                    actionLabel: searching || !can.editProducts ? null : l.addProduct,
                    onAction: () => context.push(Routes.productNew),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 160),
                  itemCount: items.length + (items.length >= _limit ? 1 : 0),
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: AppSpacing.md),
                  itemBuilder: (context, i) {
                    if (i == items.length) {
                      return TextButton(
                        onPressed: () {
                          _limit += ProductsRepository.pageSize;
                          _reload();
                        },
                        child: Text(l.loadMore),
                      );
                    }
                    return _ProductTile(item: items[i], showCost: can.seeCost);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: can.editProducts
          ? Padding(
              padding: const EdgeInsets.only(bottom: 72),
              child: FloatingActionButton(
                key: const Key('fab_add_product'),
                heroTag: 'add_product',
                tooltip: l.addProduct,
                onPressed: () => context.push(Routes.productNew),
                child: const Icon(Icons.add_rounded),
              ),
            )
          : null,
    );
  }
}

final _categoriesProvider = StreamProvider.autoDispose((ref) => ref.watch(productsRepoProvider).watchCategories());

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.item, required this.showCost});

  final ProductListItem item;
  final bool showCost;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final p = item.product;
    final stockColor = item.isOut ? c.danger : (item.isLow ? c.warning : c.textSecondary);
    return ListTile(
      onTap: () => context.push(Routes.product(p.id)),
      leading: CircleAvatar(
        backgroundColor: c.primaryContainer,
        child: Icon(p.tracksImei ? Icons.phone_android_rounded : Icons.inventory_2_outlined, color: c.primary),
      ),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Ltr(Text(p.sku, style: theme.textTheme.bodySmall)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Ltr(Text(Fmt.money(p.salePrice), style: theme.textTheme.titleSmall)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.isOut || item.isLow) ...[
                Icon(Icons.warning_amber_rounded, size: 14, color: stockColor),
                const SizedBox(width: 2),
              ],
              Text(l.qtyLeft(Fmt.qty(item.qty)), style: theme.textTheme.labelMedium?.copyWith(color: stockColor)),
            ],
          ),
        ],
      ),
    );
  }
}
