import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../converters.dart';
import 'base.dart';

@DataClassName('UsedPhonePurchase')
class UsedPhonePurchases extends Table with BaseColumns {
  IntColumn get docSeq => integer()();
  TextColumn get docNo => text()();
  TextColumn get sellerPartyId => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get sellerCnic => text().nullable()();
  /// Encrypted files in app-private storage (spec Section 9).
  TextColumn get cnicFrontPath => text().nullable()();
  TextColumn get cnicBackPath => text().nullable()();
  TextColumn get devicePhotosJson => text().withDefault(const Constant('[]'))();
  TextColumn get model => text()();
  TextColumn get productId => text()();
  TextColumn get imeiUnitId => text()();
  TextColumn get grade => textEnum<ConditionGrade>()();
  IntColumn get price => integer().map(const MoneyConverter())();
  TextColumn get method => textEnum<PaymentMethod>()();
  /// When identity data was purged (retention or on request).
  DateTimeColumn get identityPurgedAt => dateTime().nullable()();
  TextColumn get status => textEnum<DocStatus>()();
  TextColumn get reversesId => text().nullable()();
}

@DataClassName('RepairJob')
class RepairJobs extends Table with BaseColumns {
  IntColumn get jobSeq => integer()();
  TextColumn get jobNo => text()();
  TextColumn get partyId => text()();
  TextColumn get deviceModel => text()();
  TextColumn get imei => text().nullable()();
  TextColumn get problem => text()();
  IntColumn get estimate => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Final bill (labour + parts charge) set on delivery.
  IntColumn get finalAmount => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  TextColumn get status => textEnum<RepairStatus>()();
  TextColumn get technicianId => text().nullable()();
  DateTimeColumn get expectedDate => dateTime().nullable()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  TextColumn get saleId => text().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('RepairPart')
class RepairParts extends Table with BaseColumns {
  TextColumn get jobId => text()();
  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get action => textEnum<RepairPartAction>()();
  IntColumn get qty => integer()();
  /// Cost per unit at issue time.
  IntColumn get unitCost => integer().map(const MoneyConverter())();
  /// Total cost moved (qty × avg cost, rounded).
  IntColumn get costTotal => integer().map(const MoneyConverter())();
  /// What the customer is charged for this part (informational).
  IntColumn get charge => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
}

@DataClassName('RepairStatusLog')
class RepairStatusLogs extends Table with BaseColumns {
  TextColumn get jobId => text()();
  TextColumn get fromStatus => textEnum<RepairStatus>().nullable()();
  TextColumn get toStatus => textEnum<RepairStatus>()();
  TextColumn get note => text().nullable()();
}

@DataClassName('QistPlan')
class QistPlans extends Table with BaseColumns {
  TextColumn get saleId => text()();
  TextColumn get partyId => text()();
  TextColumn get guarantorName => text().nullable()();
  TextColumn get guarantorPhone => text().nullable()();
  /// P — cash price of goods.
  IntColumn get cashPrice => integer().map(const MoneyConverter())();
  /// M — markup.
  IntColumn get markup => integer().map(const MoneyConverter())();
  /// T = P + M.
  IntColumn get total => integer().map(const MoneyConverter())();
  /// D — down payment.
  IntColumn get downPayment => integer().map(const MoneyConverter())();
  IntColumn get installments => integer()();
  TextColumn get frequency => textEnum<QistFrequency>()();
  DateTimeColumn get startDate => dateTime()();
  TextColumn get status => textEnum<QistPlanStatus>()();
}

@DataClassName('QistScheduleRow')
class QistSchedule extends Table with BaseColumns {
  TextColumn get planId => text()();
  IntColumn get seq => integer()();
  DateTimeColumn get dueDate => dateTime()();
  IntColumn get amountDue => integer().map(const MoneyConverter())();
  IntColumn get amountPaid => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  TextColumn get status => textEnum<QistRowStatus>()();
}
