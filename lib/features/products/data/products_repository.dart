import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';

enum StockFilter { all, low, out, imei }

/// A product row with its total stock across variants.
class ProductListItem {
  const ProductListItem(this.product, this.qty, this.value);

  final Product product;
  final int qty;
  final Money value;

  bool get isLow => qty > 0 && qty <= product.minStock;
  bool get isOut => qty <= 0;
}

/// What the POS search found: a product (and variant), possibly a specific
/// IMEI unit when the user typed or scanned an IMEI.
class SaleSearchHit {
  const SaleSearchHit({required this.product, this.variant, required this.qty, this.imeiUnit});

  final Product product;
  final ProductVariant? variant;
  final int qty;
  final ImeiUnit? imeiUnit;

  Money get price => variant?.salePrice ?? product.salePrice;
  String get label => variant == null ? product.name : '${product.name} ${variant!.label}';
}

/// Read side for products and stock (spec 5.5). Lists page 50 rows at a
/// time (spec Section 6).
class ProductsRepository {
  ProductsRepository(this.db);

  final AppDatabase db;

  static const pageSize = 50;

  String _like(String s) => '%${s.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

  Selectable<ProductListItem> list({
    String search = '',
    StockFilter filter = StockFilter.all,
    String? categoryId,
    String? brandId,
    int limit = pageSize,
    bool activeOnly = true,
  }) {
    final where = <String>[if (activeOnly) 'p.is_active = 1'];
    final vars = <Variable>[];
    final q = search.trim();
    if (q.isNotEmpty) {
      where.add("(p.name LIKE ? ESCAPE '\\' OR p.name_ur LIKE ? ESCAPE '\\' OR p.sku LIKE ? ESCAPE '\\' "
          'OR EXISTS (SELECT 1 FROM barcodes bc WHERE bc.product_id = p.id AND bc.code = ?) '
          "OR EXISTS (SELECT 1 FROM imei_units u WHERE u.product_id = p.id AND (u.imei1 = ? OR u.imei2 = ?)))");
      vars.addAll([
        Variable.withString(_like(q)),
        Variable.withString(_like(q)),
        Variable.withString(_like(q)),
        Variable.withString(q),
        Variable.withString(q),
        Variable.withString(q),
      ]);
    }
    if (categoryId != null) {
      where.add('p.category_id = ?');
      vars.add(Variable.withString(categoryId));
    }
    if (brandId != null) {
      where.add('p.brand_id = ?');
      vars.add(Variable.withString(brandId));
    }
    if (filter == StockFilter.imei) where.add('p.tracks_imei = 1');
    final having = switch (filter) {
      StockFilter.low => 'HAVING qty > 0 AND qty <= p.min_stock',
      StockFilter.out => 'HAVING qty <= 0',
      _ => '',
    };
    return db.customSelect(
      'SELECT p.*, COALESCE(SUM(b.qty_on_hand), 0) AS qty, COALESCE(SUM(b.value), 0) AS val '
      'FROM products p LEFT JOIN stock_balances b ON b.product_id = p.id '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'GROUP BY p.id $having ORDER BY p.name COLLATE NOCASE LIMIT ?',
      variables: [...vars, Variable.withInt(limit)],
      readsFrom: {db.products, db.stockBalances, db.barcodes, db.imeiUnits},
    ).asyncMap((r) async => ProductListItem(await db.products.mapFromRow(r), r.read<int>('qty'), Money(r.read<int>('val'))));
  }

  Future<int> lowStockCount() async {
    final r = await db.customSelect(
      'SELECT COUNT(*) n FROM (SELECT p.id, p.min_stock m, COALESCE(SUM(b.qty_on_hand),0) q FROM products p '
      'LEFT JOIN stock_balances b ON b.product_id = p.id WHERE p.is_active = 1 GROUP BY p.id) WHERE q <= m AND m > 0',
    ).getSingle();
    return r.read<int>('n');
  }

  Stream<int> watchLowStockCount() => db
      .customSelect(
        'SELECT COUNT(*) n FROM (SELECT p.id, p.min_stock m, COALESCE(SUM(b.qty_on_hand),0) q FROM products p '
        'LEFT JOIN stock_balances b ON b.product_id = p.id WHERE p.is_active = 1 GROUP BY p.id) WHERE q <= m AND m > 0',
        readsFrom: {db.products, db.stockBalances},
      )
      .watchSingle()
      .map((r) => r.read<int>('n'));

  Stream<Product?> watchProduct(String id) => (db.select(db.products)..where((p) => p.id.equals(id))).watchSingleOrNull();

  Future<Product?> product(String id) => (db.select(db.products)..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<List<StockBalance>> watchBalances(String productId) =>
      (db.select(db.stockBalances)..where((b) => b.productId.equals(productId))).watch();

  Stream<List<ProductVariant>> watchVariants(String productId) =>
      (db.select(db.productVariants)..where((v) => v.productId.equals(productId))).watch();

  Future<List<ProductVariant>> variants(String productId) =>
      (db.select(db.productVariants)..where((v) => v.productId.equals(productId) & v.isActive.equals(true))).get();

  Stream<List<Barcode>> watchBarcodes(String productId) =>
      (db.select(db.barcodes)..where((b) => b.productId.equals(productId))).watch();

  Stream<List<StockMovement>> watchMovements(String productId, {int limit = pageSize}) => (db.select(db.stockMovements)
        ..where((m) => m.productId.equals(productId))
        ..orderBy([(m) => OrderingTerm.desc(m.date), (m) => OrderingTerm.desc(m.id)])
        ..limit(limit))
      .watch();

  Stream<List<ImeiUnit>> watchImeis(String productId) => (db.select(db.imeiUnits)
        ..where((u) => u.productId.equals(productId))
        ..orderBy([(u) => OrderingTerm.asc(u.status), (u) => OrderingTerm.desc(u.createdAt)]))
      .watch();

  Future<List<ImeiUnit>> inStockImeis(String productId, {String? variantId}) => (db.select(db.imeiUnits)
        ..where((u) =>
            u.productId.equals(productId) &
            u.status.equalsValue(ImeiStatus.inStock) &
            (variantId == null ? const Constant(true) : u.variantId.equals(variantId)))
        ..orderBy([(u) => OrderingTerm.asc(u.createdAt)]))
      .get();

  Stream<List<Category>> watchCategories() =>
      (db.select(db.categories)..where((c) => c.isActive.equals(true))..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  Stream<List<Brand>> watchBrands() =>
      (db.select(db.brands)..where((c) => c.isActive.equals(true))..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  Stream<List<UnitRow>> watchUnits() => (db.select(db.units)..orderBy([(u) => OrderingTerm.asc(u.factor)])).watch();

  Future<List<UnitRow>> units() => db.select(db.units).get();

  /// POS search by name, SKU, barcode or IMEI (spec 5.3 step 1). Exact
  /// barcode / IMEI matches come first.
  Future<List<SaleSearchHit>> searchForSale(String query, {int limit = 30}) async {
    final q = query.trim();
    final hits = <SaleSearchHit>[];
    if (q.isNotEmpty) {
      final unit = await (db.select(db.imeiUnits)
            ..where((u) => (u.imei1.equals(q) | u.imei2.equals(q)) & u.status.equalsValue(ImeiStatus.inStock)))
          .getSingleOrNull();
      if (unit != null) {
        final p = await product(unit.productId);
        if (p != null && p.isActive) {
          final v = unit.variantId == null
              ? null
              : await (db.select(db.productVariants)..where((x) => x.id.equals(unit.variantId!))).getSingleOrNull();
          hits.add(SaleSearchHit(product: p, variant: v, qty: 1, imeiUnit: unit));
          return hits;
        }
      }
      final code = await (db.select(db.barcodes)..where((b) => b.code.equals(q))).getSingleOrNull();
      if (code != null) {
        final p = await product(code.productId);
        if (p != null && p.isActive) {
          final v = code.variantId == null
              ? null
              : await (db.select(db.productVariants)..where((x) => x.id.equals(code.variantId!))).getSingleOrNull();
          hits.add(SaleSearchHit(product: p, variant: v, qty: await _qty(p.id, v?.id)));
          return hits;
        }
      }
    }
    for (final item in await list(search: q, limit: limit).get()) {
      if (item.product.hasVariants) {
        for (final v in await variants(item.product.id)) {
          hits.add(SaleSearchHit(product: item.product, variant: v, qty: await _qty(item.product.id, v.id)));
        }
      } else {
        hits.add(SaleSearchHit(product: item.product, qty: item.qty));
      }
    }
    return hits;
  }

  Future<int> _qty(String productId, String? variantId) async {
    final b = await (db.select(db.stockBalances)
          ..where((x) => x.productId.equals(productId) & (variantId == null ? x.variantId.isNull() : x.variantId.equals(variantId))))
        .getSingleOrNull();
    return b?.qtyOnHand ?? 0;
  }
}
