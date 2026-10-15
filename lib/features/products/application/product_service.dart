import 'package:drift/drift.dart';

import '../../../core/accounting/posting.dart';
import '../../../core/accounting/system_accounts.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';

/// One IMEI-tracked unit being added (opening stock or purchase).
class ImeiInput {
  const ImeiInput({required this.imei1, this.imei2, this.serial, this.cost, this.grade});

  final String imei1;
  final String? imei2;
  final String? serial;

  /// Per-unit cost. For purchases this is computed from the line instead.
  final Money? cost;
  final ConditionGrade? grade;
}

class ProductInput {
  const ProductInput({
    required this.name,
    this.nameUr,
    this.sku,
    this.categoryId,
    this.brandId,
    this.unitId,
    this.altUnitId,
    required this.salePrice,
    this.minSalePrice = Money.zero,
    this.minStock = 0,
    this.tracksImei = false,
    this.warrantyDays = 0,
    this.barcodes = const [],
  });

  final String name;
  final String? nameUr;
  final String? sku;
  final String? categoryId;
  final String? brandId;
  final String? unitId;
  final String? altUnitId;
  final Money salePrice;
  final Money minSalePrice;
  final int minStock;
  final bool tracksImei;
  final int warrantyDays;
  final List<String> barcodes;
}

/// Products, variants, barcodes, opening stock and stock adjustments
/// (spec 5.5). Every stock change goes through the posting engine.
class ProductService {
  ProductService(this.db, this.ctx) : posting = PostingService(db, ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  final PostingService posting;

  /// Creates a product, optionally with opening stock at [openingCost] per
  /// base unit, or [openingImeis] for IMEI items.
  Future<String> createProduct(
    ProductInput input, {
    int openingQty = 0,
    Money openingCost = Money.zero,
    List<ImeiInput> openingImeis = const [],
    List<({String label, Money salePrice, String? sku})> variants = const [],
  }) {
    if (input.name.trim().isEmpty) throw const PostingException(PostingError.invalidInput, 'name');
    if (input.salePrice.isNegative) throw const PostingException(PostingError.invalidAmount);
    return posting.run((p) async {
      final id = newId();
      final sku = (input.sku == null || input.sku!.trim().isEmpty) ? await _autoSku(p) : input.sku!.trim();
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: id,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            name: input.name.trim(),
            nameUr: Value(input.nameUr),
            sku: sku,
            categoryId: Value(input.categoryId),
            brandId: Value(input.brandId),
            unitId: Value(input.unitId),
            altUnitId: Value(input.altUnitId),
            salePrice: input.salePrice,
            minSalePrice: Value(input.minSalePrice),
            minStock: Value(input.minStock),
            tracksImei: Value(input.tracksImei),
            hasVariants: Value(variants.isNotEmpty),
            warrantyDays: Value(input.warrantyDays),
          ));
      for (final code in input.barcodes.where((c) => c.trim().isNotEmpty)) {
        await _insertBarcode(p, id, null, code.trim());
      }
      for (final v in variants) {
        await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
              id: newId(),
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              productId: id,
              label: v.label,
              sku: v.sku ?? '$sku-${v.label.replaceAll(' ', '').toUpperCase()}',
              salePrice: v.salePrice,
            ));
      }
      await p.audit('product', id, 'create', after: {'name': input.name, 'sku': sku});
      if (openingQty > 0 || openingImeis.isNotEmpty) {
        await _postOpening(p, id, null, openingQty, openingCost, openingImeis, input.tracksImei);
      }
      return id;
    });
  }

  Future<void> updateProduct(String id, ProductInput input) async {
    await posting.run((p) async {
      final before = await (db.select(db.products)..where((x) => x.id.equals(id))).getSingle();
      await (db.update(db.products)..where((x) => x.id.equals(id))).write(ProductsCompanion(
        name: Value(input.name.trim()),
        nameUr: Value(input.nameUr),
        sku: input.sku == null || input.sku!.isEmpty ? const Value.absent() : Value(input.sku!),
        categoryId: Value(input.categoryId),
        brandId: Value(input.brandId),
        unitId: Value(input.unitId),
        altUnitId: Value(input.altUnitId),
        salePrice: Value(input.salePrice),
        minSalePrice: Value(input.minSalePrice),
        minStock: Value(input.minStock),
        // tracks_imei cannot change once stock exists (it would break IMEI
        // invariants); the UI disables the switch.
        warrantyDays: Value(input.warrantyDays),
        updatedAt: Value(p.now),
      ));
      final existing = (await (db.select(db.barcodes)..where((b) => b.productId.equals(id) & b.variantId.isNull())).get())
          .map((b) => b.code)
          .toSet();
      for (final code in input.barcodes.map((c) => c.trim()).where((c) => c.isNotEmpty)) {
        if (!existing.contains(code)) await _insertBarcode(p, id, null, code);
      }
      await p.audit('product', id, 'update_master',
          before: {'name': before.name, 'salePrice': before.salePrice.paisa},
          after: {'name': input.name, 'salePrice': input.salePrice.paisa});
    });
  }

  Future<void> setActive(String id, bool active) => posting.run((p) async {
        await (db.update(db.products)..where((x) => x.id.equals(id)))
            .write(ProductsCompanion(isActive: Value(active), updatedAt: Value(p.now)));
        await p.audit('product', id, active ? 'activate' : 'deactivate');
      });

  /// Opening stock for an existing product (spec 8.1: Dr Inventory,
  /// Cr OPENING_EQUITY at qty × opening cost).
  Future<void> addOpeningStock(String productId,
      {String? variantId, int qty = 0, Money unitCost = Money.zero, List<ImeiInput> imeis = const []}) {
    return posting.run((p) async {
      final product = await _product(productId);
      await _postOpening(p, productId, variantId, qty, unitCost, imeis, product.tracksImei);
    });
  }

  Future<void> _postOpening(Posting p, String productId, String? variantId, int qty, Money unitCost,
      List<ImeiInput> imeis, bool tracksImei) async {
    final docId = newId();
    var total = Money.zero;
    if (tracksImei) {
      if (imeis.isEmpty) throw const PostingException(PostingError.imeiRequired);
      for (final i in imeis) {
        final cost = i.cost ?? unitCost;
        final unitId = await insertImeiUnit(p, productId, variantId, i, cost, 'opening', docId);
        total += cost;
        await p.stockIn(
          productId: productId,
          variantId: variantId,
          qty: 1,
          value: cost,
          type: StockMoveType.opening,
          refType: 'opening',
          refId: docId,
          imeiUnitId: unitId,
        );
      }
    } else {
      if (qty <= 0 || unitCost.isNegative) throw const PostingException(PostingError.invalidInput, 'opening qty');
      total = unitCost.times(qty);
      await p.stockIn(
        productId: productId,
        variantId: variantId,
        qty: qty,
        value: total,
        type: StockMoveType.opening,
        refType: 'opening',
        refId: docId,
      );
    }
    p.cr(SysAccount.openingEquity, total);
    final business = await (db.select(db.businesses)..limit(1)).getSingle();
    await p.commit(date: business.goLiveDate, sourceType: 'opening_stock', sourceId: docId, memo: 'Opening stock');
  }

  /// Stock adjustment (spec 5.5): damaged, lost, found or count correction.
  ///
  /// Loss: Dr STOCK_LOSS, Cr Inventory at average cost.
  /// Gain: Dr Inventory, Cr INVENTORY_ADJUSTMENT at average cost.
  /// For count correction pass [countedQty]; otherwise pass [qty] (> 0).
  /// Requires owner PIN in the UI (spec Section 9).
  Future<String> adjustStock({
    required String productId,
    String? variantId,
    required AdjustmentReason reason,
    int qty = 0,
    int? countedQty,
    String? imeiUnitId,
    String? note,
  }) {
    return posting.run((p) async {
      final product = await _product(productId);
      final bal = await p.stockBalance(productId, variantId);
      var change = switch (reason) {
        AdjustmentReason.damaged || AdjustmentReason.lost => -qty,
        AdjustmentReason.found => qty,
        AdjustmentReason.countCorrection => (countedQty ?? bal.qtyOnHand) - bal.qtyOnHand,
      };
      final id = newId();
      Money value;

      if (product.tracksImei) {
        if (reason == AdjustmentReason.found || reason == AdjustmentReason.countCorrection) {
          throw const PostingException(PostingError.invalidInput, 'IMEI items are added by purchase');
        }
        if (imeiUnitId == null) throw const PostingException(PostingError.imeiRequired);
        final unit = await (db.select(db.imeiUnits)..where((u) => u.id.equals(imeiUnitId))).getSingle();
        if (unit.status != ImeiStatus.inStock || unit.productId != productId) {
          throw const PostingException(PostingError.imeiNotAvailable);
        }
        change = -1;
        final r = await p.stockOut(
          productId: productId,
          variantId: unit.variantId,
          qty: 1,
          value: unit.cost,
          type: StockMoveType.adjustment,
          refType: 'stock_adjustment',
          refId: id,
          imeiUnitId: unit.id,
          reason: reason.name,
          allowNegative: false,
        );
        value = r.value;
        await (db.update(db.imeiUnits)..where((u) => u.id.equals(unit.id)))
            .write(ImeiUnitsCompanion(status: const Value(ImeiStatus.writtenOff), updatedAt: Value(p.now)));
        p.dr(SysAccount.stockLoss, value);
      } else if (change < 0) {
        final r = await p.stockOut(
          productId: productId,
          variantId: variantId,
          qty: -change,
          type: StockMoveType.adjustment,
          refType: 'stock_adjustment',
          refId: id,
          reason: reason.name,
          allowNegative: false,
        );
        value = r.value;
        p.dr(SysAccount.stockLoss, value);
      } else if (change > 0) {
        final avg = bal.qtyOnHand > 0 ? bal.value.ratio(1, bal.qtyOnHand) : product.avgCost;
        value = avg.times(change);
        await p.stockIn(
          productId: productId,
          variantId: variantId,
          qty: change,
          value: value,
          type: StockMoveType.adjustment,
          refType: 'stock_adjustment',
          refId: id,
          reason: reason.name,
        );
        p.cr(SysAccount.inventoryAdjustment, value);
      } else {
        throw const PostingException(PostingError.invalidInput, 'no change');
      }

      await db.into(db.stockAdjustments).insert(StockAdjustmentsCompanion.insert(
            id: id,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            productId: productId,
            variantId: Value(variantId),
            imeiUnitId: Value(imeiUnitId),
            date: p.now,
            reason: reason,
            qtyChange: change,
            value: value,
            note: Value(note),
            status: DocStatus.posted,
          ));
      await p.commit(date: p.now, sourceType: 'stock_adjustment', sourceId: id, memo: 'Stock ${reason.name}');
      await p.audit('stock_adjustment', id, 'create', after: {'product': productId, 'qty': change, 'reason': reason.name});
      return id;
    });
  }

  /// Reverses a stock adjustment (owner PIN in the UI).
  Future<String> reverseAdjustment(String adjustmentId) => posting.run((p) async {
        final adj = await (db.select(db.stockAdjustments)..where((a) => a.id.equals(adjustmentId))).getSingleOrNull();
        if (adj == null) throw const PostingException(PostingError.notFound);
        if (adj.status != DocStatus.posted) throw const PostingException(PostingError.alreadyReversed);
        if (adj.qtyChange > 0) {
          final bal = await p.stockBalance(adj.productId, adj.variantId);
          if (bal.qtyOnHand < adj.qtyChange) throw const PostingException(PostingError.insufficientStock);
        }
        final revId = newId();
        await db.into(db.stockAdjustments).insert(StockAdjustmentsCompanion.insert(
              id: revId,
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              productId: adj.productId,
              variantId: Value(adj.variantId),
              imeiUnitId: Value(adj.imeiUnitId),
              date: p.now,
              reason: adj.reason,
              qtyChange: -adj.qtyChange,
              value: adj.value,
              status: DocStatus.reversal,
              reversesId: Value(adj.id),
            ));
        await p.mirrorSource(sourceId: adj.id, reversalId: revId, sourceType: 'stock_adjustment');
        if (adj.imeiUnitId != null) {
          await (db.update(db.imeiUnits)..where((u) => u.id.equals(adj.imeiUnitId!)))
              .write(ImeiUnitsCompanion(status: const Value(ImeiStatus.inStock), updatedAt: Value(p.now)));
        }
        await (db.update(db.stockAdjustments)..where((a) => a.id.equals(adj.id)))
            .write(StockAdjustmentsCompanion(status: const Value(DocStatus.reversed), updatedAt: Value(p.now)));
        await p.audit('stock_adjustment', adj.id, 'reverse');
        return revId;
      });

  Future<String> addVariant(String productId, {required String label, required Money salePrice, String? sku}) {
    return posting.run((p) async {
      final product = await _product(productId);
      final id = newId();
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: id,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            productId: productId,
            label: label,
            sku: sku ?? '${product.sku}-${label.replaceAll(' ', '').toUpperCase()}',
            salePrice: salePrice,
          ));
      await (db.update(db.products)..where((x) => x.id.equals(productId)))
          .write(ProductsCompanion(hasVariants: const Value(true), updatedAt: Value(p.now)));
      return id;
    });
  }

  Future<String> addBarcode(String productId, String code, {String? variantId}) =>
      posting.run((p) => _insertBarcode(p, productId, variantId, code.trim()));

  Future<String> _insertBarcode(Posting p, String productId, String? variantId, String code) async {
    final clash = await (db.select(db.barcodes)..where((b) => b.code.equals(code))).getSingleOrNull();
    if (clash != null) throw PostingException(PostingError.invalidInput, 'barcode $code already used');
    final id = newId();
    await db.into(db.barcodes).insert(BarcodesCompanion.insert(
          id: id,
          businessId: p.businessId,
          createdAt: p.now,
          updatedAt: p.now,
          createdBy: Value(p.userId),
          productId: productId,
          variantId: Value(variantId),
          code: code,
        ));
    return id;
  }

  Future<String> createCategory(String name, {String? parentId}) => posting.run((p) async {
        final id = newId();
        await db.into(db.categories).insert(CategoriesCompanion.insert(
            id: id,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            name: name.trim(),
            parentId: Value(parentId)));
        return id;
      });

  Future<String> createBrand(String name) => posting.run((p) async {
        final id = newId();
        await db.into(db.brands).insert(BrandsCompanion.insert(
            id: id,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            name: name.trim()));
        return id;
      });

  Future<Product> _product(String id) async {
    final row = await (db.select(db.products)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (row == null) throw PostingException(PostingError.notFound, 'product $id');
    return row;
  }

  Future<String> _autoSku(Posting p) async => 'SKU-${(await p.nextSeq('sku')).toString().padLeft(5, '0')}';
}

/// Inserts an in-stock IMEI unit after checking the IMEI is not already in
/// stock or in repair (spec 8: an IMEI can be in_stock in only one place).
Future<String> insertImeiUnit(Posting p, String productId, String? variantId, ImeiInput i, Money cost,
    String refType, String refId) async {
  final db = p.db;
  final imei = i.imei1.trim();
  if (imei.isEmpty) throw const PostingException(PostingError.imeiRequired);
  for (final code in [imei, if (i.imei2 != null && i.imei2!.trim().isNotEmpty) i.imei2!.trim()]) {
    final clash = await (db.select(db.imeiUnits)
          ..where((u) =>
              (u.imei1.equals(code) | u.imei2.equals(code)) &
              u.status.isInValues([ImeiStatus.inStock, ImeiStatus.inRepair])))
        .get();
    if (clash.isNotEmpty) throw PostingException(PostingError.imeiDuplicate, code);
  }
  final id = newId();
  await db.into(db.imeiUnits).insert(ImeiUnitsCompanion.insert(
        id: id,
        businessId: p.businessId,
        createdAt: p.now,
        updatedAt: p.now,
        createdBy: Value(p.userId),
        productId: productId,
        variantId: Value(variantId),
        imei1: imei,
        imei2: Value(i.imei2?.trim().isEmpty ?? true ? null : i.imei2!.trim()),
        serial: Value(i.serial),
        status: ImeiStatus.inStock,
        purchaseRefType: Value(refType),
        purchaseRefId: Value(refId),
        cost: cost,
        conditionGrade: Value(i.grade),
      ));
  return id;
}
