import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../converters.dart';
import 'base.dart';

@DataClassName('Party')
class Parties extends Table with BaseColumns {
  TextColumn get type => textEnum<PartyType>()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get cnic => text().nullable()();
  TextColumn get address => text().nullable()();
  /// Signed: positive = party owes the shop (Lena), negative = shop owes.
  IntColumn get openingBalance => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Zero = no limit.
  IntColumn get creditLimit => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('Sale')
class Sales extends Table with BaseColumns {
  IntColumn get invoiceSeq => integer()();
  TextColumn get invoiceNo => text()();
  TextColumn get partyId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  /// Σ qty × unit price, before any discount.
  IntColumn get gross => integer().map(const MoneyConverter())();
  /// Σ line totals (gross − line discounts).
  IntColumn get subtotal => integer().map(const MoneyConverter())();
  /// Invoice-level discount.
  IntColumn get discount => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get tax => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get delivery => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Qist markup (Pro); zero otherwise.
  IntColumn get markup => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get total => integer().map(const MoneyConverter())();
  IntColumn get paid => integer().map(const MoneyConverter())();
  TextColumn get paidMethod => textEnum<PaymentMethod>()();
  IntColumn get due => integer().map(const MoneyConverter())();
  TextColumn get paymentMode => textEnum<SalePaymentMode>()();
  TextColumn get status => textEnum<DocStatus>()();
  TextColumn get reversesId => text().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('SaleItem')
class SaleItems extends Table with BaseColumns {
  TextColumn get saleId => text()();
  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get imeiUnitId => text().nullable()();
  /// Snapshot of the product name at sale time.
  TextColumn get description => text()();
  TextColumn get unitId => text().nullable()();
  /// Quantity in the unit sold (e.g. 2 cartons).
  IntColumn get unitQty => integer()();
  /// Quantity in base units (e.g. 48 pcs). Stock moves by this.
  IntColumn get qty => integer()();
  /// Price per sold unit (per carton when sold by carton).
  IntColumn get unitPrice => integer().map(const MoneyConverter())();
  IntColumn get discount => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// unitQty × unitPrice − discount.
  IntColumn get lineTotal => integer().map(const MoneyConverter())();
  /// lineTotal minus this line's share of the invoice discount.
  IntColumn get netAmount => integer().map(const MoneyConverter())();
  /// This line's share of invoice tax.
  IntColumn get taxAmount => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Average cost per base unit at sale time (spec 8.1).
  IntColumn get unitCostSnapshot => integer().map(const MoneyConverter())();
  /// Exact COGS posted for this line (avoids rounding drift on returns).
  IntColumn get costTotal => integer().map(const MoneyConverter())();
}

@DataClassName('SaleReturn')
class SaleReturns extends Table with BaseColumns {
  IntColumn get returnSeq => integer()();
  TextColumn get returnNo => text()();
  TextColumn get saleId => text()();
  TextColumn get partyId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  /// R: returned value after prorated discount and tax.
  IntColumn get amount => integer().map(const MoneyConverter())();
  /// Part of R that reduced the invoice's remaining due.
  IntColumn get appliedToDue => integer().map(const MoneyConverter())();
  IntColumn get refunded => integer().map(const MoneyConverter())();
  TextColumn get refundMethod => textEnum<PaymentMethod>().nullable()();
  /// Part kept as customer credit (advance).
  IntColumn get keptAsCredit => integer().map(const MoneyConverter())();
  TextColumn get status => textEnum<DocStatus>()();
  TextColumn get reversesId => text().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('SaleReturnItem')
class SaleReturnItems extends Table with BaseColumns {
  TextColumn get returnId => text()();
  TextColumn get saleItemId => text()();
  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get imeiUnitId => text().nullable()();
  /// Base units returned.
  IntColumn get qty => integer()();
  /// Value returned excluding tax.
  IntColumn get amount => integer().map(const MoneyConverter())();
  IntColumn get taxAmount => integer().map(const MoneyConverter())();
  IntColumn get costAmount => integer().map(const MoneyConverter())();
}

@DataClassName('Purchase')
class Purchases extends Table with BaseColumns {
  IntColumn get billSeq => integer()();
  TextColumn get billNo => text()();
  TextColumn get supplierBillNo => text().nullable()();
  TextColumn get partyId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  IntColumn get subtotal => integer().map(const MoneyConverter())();
  IntColumn get discount => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Freight and purchase tax paid to the supplier; added to inventory cost.
  IntColumn get extraCost => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get total => integer().map(const MoneyConverter())();
  IntColumn get paid => integer().map(const MoneyConverter())();
  TextColumn get paidMethod => textEnum<PaymentMethod>()();
  IntColumn get due => integer().map(const MoneyConverter())();
  TextColumn get status => textEnum<DocStatus>()();
  TextColumn get reversesId => text().nullable()();
  TextColumn get billPhotoPath => text().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('PurchaseItem')
class PurchaseItems extends Table with BaseColumns {
  TextColumn get purchaseId => text()();
  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get description => text()();
  TextColumn get unitId => text().nullable()();
  IntColumn get unitQty => integer()();
  IntColumn get qty => integer()();
  /// Cost per purchased unit as entered.
  IntColumn get unitCost => integer().map(const MoneyConverter())();
  IntColumn get lineTotal => integer().map(const MoneyConverter())();
  /// Inventory value added: lineTotal − discount share + extra cost share.
  IntColumn get netCost => integer().map(const MoneyConverter())();
}

@DataClassName('PurchaseReturn')
class PurchaseReturns extends Table with BaseColumns {
  IntColumn get returnSeq => integer()();
  TextColumn get returnNo => text()();
  TextColumn get purchaseId => text()();
  TextColumn get partyId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  IntColumn get appliedToDue => integer().map(const MoneyConverter())();
  IntColumn get refunded => integer().map(const MoneyConverter())();
  TextColumn get refundMethod => textEnum<PaymentMethod>().nullable()();
  IntColumn get keptAsCredit => integer().map(const MoneyConverter())();
  TextColumn get status => textEnum<DocStatus>()();
  TextColumn get reversesId => text().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('PurchaseReturnItem')
class PurchaseReturnItems extends Table with BaseColumns {
  TextColumn get returnId => text()();
  TextColumn get purchaseItemId => text()();
  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get imeiUnitId => text().nullable()();
  IntColumn get qty => integer()();
  IntColumn get amount => integer().map(const MoneyConverter())();
}

@DataClassName('Payment')
class Payments extends Table with BaseColumns {
  TextColumn get direction => textEnum<PaymentDirection>()();
  TextColumn get partyId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  TextColumn get method => textEnum<PaymentMethod>()();
  TextColumn get accountId => text()();
  TextColumn get reference => text().nullable()();
  /// Optional link, e.g. repair job advance or qist plan.
  TextColumn get refType => text().nullable()();
  TextColumn get refId => text().nullable()();
  TextColumn get status => textEnum<DocStatus>()();
  TextColumn get reversesId => text().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('PaymentAllocation')
class PaymentAllocations extends Table with BaseColumns {
  TextColumn get sourceType => textEnum<AllocSource>()();
  /// The payment (or return) that settles the document.
  TextColumn get paymentId => text()();
  TextColumn get docType => textEnum<AllocDocType>()();
  TextColumn get docId => text()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  BoolColumn get isVoid => boolean().withDefault(const Constant(false))();
}

@DataClassName('Expense')
class Expenses extends Table with BaseColumns {
  TextColumn get categoryId => text()();
  DateTimeColumn get date => dateTime()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  TextColumn get method => textEnum<PaymentMethod>()();
  TextColumn get accountId => text()();
  TextColumn get note => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get status => textEnum<DocStatus>()();
  TextColumn get reversesId => text().nullable()();
}

@DataClassName('ExpenseCategory')
class ExpenseCategories extends Table with BaseColumns {
  TextColumn get name => text()();
  /// Stable key for built-in categories (rent, bijli ...); null for custom.
  TextColumn get systemKey => text().nullable()();
  TextColumn get accountId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('StockAdjustment')
class StockAdjustments extends Table with BaseColumns {
  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get imeiUnitId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  TextColumn get reason => textEnum<AdjustmentReason>()();
  IntColumn get qtyChange => integer()();
  IntColumn get value => integer().map(const MoneyConverter())();
  TextColumn get note => text().nullable()();
  TextColumn get status => textEnum<DocStatus>()();
  TextColumn get reversesId => text().nullable()();
}
