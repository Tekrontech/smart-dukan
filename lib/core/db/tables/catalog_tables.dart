import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../converters.dart';
import 'base.dart';

@DataClassName('Category')
class Categories extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('Brand')
class Brands extends Table with BaseColumns {
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// A unit of measure. `factor` converts to [baseUnitId]: carton = 24 pcs
/// means symbol "ctn", baseUnitId = pcs, factor = 24. Base units have
/// factor 1 and no baseUnitId.
@DataClassName('UnitRow')
class Units extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get symbol => text()();
  TextColumn get baseUnitId => text().nullable()();
  IntColumn get factor => integer().withDefault(const Constant(1))();
}

@DataClassName('Product')
class Products extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get nameUr => text().nullable()();
  TextColumn get sku => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get brandId => text().nullable()();
  /// Base unit; stock quantities are always in this unit.
  TextColumn get unitId => text().nullable()();
  /// Optional larger unit (e.g. carton) offered at sale/purchase.
  TextColumn get altUnitId => text().nullable()();
  IntColumn get salePrice => integer().map(const MoneyConverter())();
  IntColumn get minSalePrice => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Weighted average cost per base unit (mirror of stock_balances).
  IntColumn get avgCost => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get minStock => integer().withDefault(const Constant(0))();
  BoolColumn get tracksImei => boolean().withDefault(const Constant(false))();
  BoolColumn get hasVariants => boolean().withDefault(const Constant(false))();
  IntColumn get warrantyDays => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('ProductVariant')
class ProductVariants extends Table with BaseColumns {
  TextColumn get productId => text()();
  TextColumn get label => text()();
  TextColumn get sku => text()();
  IntColumn get salePrice => integer().map(const MoneyConverter())();
  IntColumn get avgCost => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('Barcode')
class Barcodes extends Table with BaseColumns {
  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get code => text().unique()();
}

/// Every stock change. `stock_balances` must always equal the sum of these
/// (spec Section 8 invariants).
@DataClassName('StockMovement')
class StockMovements extends Table with BaseColumns {
  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  /// `productId:variantId` — the stock bucket.
  TextColumn get stockKey => text()();
  IntColumn get qtyChange => integer()();
  IntColumn get unitCost => integer().map(const MoneyConverter())();
  /// Change in inventory value (paisa). Σ value_change = stock value.
  IntColumn get valueChange => integer().map(const MoneyConverter())();
  TextColumn get type => textEnum<StockMoveType>()();
  TextColumn get refType => text()();
  TextColumn get refId => text()();
  TextColumn get imeiUnitId => text().nullable()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get date => dateTime()();
}

@DataClassName('StockBalance')
class StockBalances extends Table with BaseColumns {
  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get stockKey => text().unique()();
  IntColumn get qtyOnHand => integer().withDefault(const Constant(0))();
  IntColumn get value => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
}

@DataClassName('ImeiUnit')
class ImeiUnits extends Table with BaseColumns {
  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get imei1 => text()();
  TextColumn get imei2 => text().nullable()();
  TextColumn get serial => text().nullable()();
  TextColumn get status => textEnum<ImeiStatus>()();
  TextColumn get purchaseRefType => text().nullable()();
  TextColumn get purchaseRefId => text().nullable()();
  TextColumn get saleRefId => text().nullable()();
  IntColumn get cost => integer().map(const MoneyConverter())();
  TextColumn get conditionGrade => textEnum<ConditionGrade>().nullable()();
  DateTimeColumn get warrantyUntil => dateTime().nullable()();
}
