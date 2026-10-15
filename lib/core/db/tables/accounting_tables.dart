import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../converters.dart';
import 'base.dart';

@DataClassName('Account')
class Accounts extends Table with BaseColumns {
  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get type => textEnum<AccountType>()();
  /// CASH, BANK, WALLET, AR, AP, INVENTORY, SALES, ... or EXPENSE_<key>.
  TextColumn get systemKey => text().unique()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('JournalEntry')
class JournalEntries extends Table with BaseColumns {
  DateTimeColumn get date => dateTime()();
  /// Document table that produced the entry, e.g. `sale`, `payment`.
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text()();
  TextColumn get memo => text().withDefault(const Constant(''))();
  /// Set on a reversal entry: the entry it mirrors.
  TextColumn get reversesId => text().nullable()();
}

@DataClassName('JournalLine')
class JournalLines extends Table with BaseColumns {
  TextColumn get entryId => text()();
  TextColumn get accountId => text()();
  TextColumn get partyId => text().nullable()();
  IntColumn get debit => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get credit => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Optional link to the document this AR/AP line belongs to (repair job,
  /// qist plan) so its outstanding balance can be read from the journal.
  TextColumn get refType => text().nullable()();
  TextColumn get refId => text().nullable()();
}

@DataClassName('CashClosing')
class CashClosings extends Table with BaseColumns {
  /// Local calendar day being closed (midnight).
  DateTimeColumn get date => dateTime()();
  IntColumn get openingCash => integer().map(const MoneyConverter())();
  IntColumn get expectedCash => integer().map(const MoneyConverter())();
  IntColumn get countedCash => integer().map(const MoneyConverter())();
  IntColumn get difference => integer().map(const MoneyConverter())();
  TextColumn get denominationsJson => text().withDefault(const Constant('{}'))();
  TextColumn get closedBy => text().nullable()();
  TextColumn get note => text().nullable()();
}
