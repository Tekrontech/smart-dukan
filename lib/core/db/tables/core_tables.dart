import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import 'base.dart';

@DataClassName('Business')
class Businesses extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get ownerName => text().withDefault(const Constant(''))();
  TextColumn get phone => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get businessType => textEnum<BusinessType>()();
  TextColumn get logoPath => text().nullable()();
  TextColumn get invoicePrefix => text().withDefault(const Constant('INV-'))();
  TextColumn get invoiceFooter => text().nullable()();
  TextColumn get invoiceTerms => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('PKR'))();
  /// Go-live date: all opening entries are dated this day (spec 8.1).
  DateTimeColumn get goLiveDate => dateTime()();
}

@DataClassName('AppUser')
class Users extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get role => textEnum<UserRole>()();
  /// `pbkdf2-sha256$<iterations>$<salt b64>$<hash b64>` (spec Section 9).
  TextColumn get pinHash => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('AppSetting')
class AppSettings extends Table with BaseColumns {
  TextColumn get key => text().unique()();
  TextColumn get value => text()();
}

@DataClassName('AuditLog')
class AuditLogs extends Table with BaseColumns {
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  /// create / reverse / update_master / login / export / view_cnic / ...
  TextColumn get action => text()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
  TextColumn get userId => text().nullable()();
}

@DataClassName('LicenseRow')
class Licenses extends Table with BaseColumns {
  TextColumn get pack => text()();
  TextColumn get deviceCode => text()();
  TextColumn get licenseId => text()();
  DateTimeColumn get issuedAt => dateTime()();
  TextColumn get signature => text()();
  /// The full activation code as received, for re-verification.
  TextColumn get code => text()();
  TextColumn get status => textEnum<LicenseStatus>()();
}

@DataClassName('SchemaMigration')
class SchemaMigrations extends Table with BaseColumns {
  IntColumn get version => integer()();
  DateTimeColumn get appliedAt => dateTime()();
}

/// Gap-free document number counters (invoice, bill, repair job ...).
@DataClassName('DocCounter')
class DocCounters extends Table with BaseColumns {
  TextColumn get key => text().unique()();
  IntColumn get lastValue => integer().withDefault(const Constant(0))();
}
