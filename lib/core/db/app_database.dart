import 'package:drift/drift.dart';

import '../domain/enums.dart';
import '../money/money.dart';
import 'converters.dart';
import 'migrations/migrations.dart';
import 'tables/accounting_tables.dart';
import 'tables/catalog_tables.dart';
import 'tables/core_tables.dart';
import 'tables/document_tables.dart';
import 'tables/pro_tables.dart';

export '../domain/enums.dart';
export '../money/money.dart';

part 'app_database.g.dart';

/// The encrypted on-device database (spec Section 7).
///
/// Open it with `openAppDatabase` (production, SQLCipher-compatible
/// encryption) or `AppDatabase(NativeDatabase.memory())` in tests.
@DriftDatabase(tables: [
  // Core
  Businesses, Users, AppSettings, AuditLogs, Licenses, SchemaMigrations, DocCounters,
  // Catalogue and stock
  Categories, Brands, Units, Products, ProductVariants, Barcodes, StockMovements, StockBalances,
  ImeiUnits,
  // Parties and documents
  Parties, Sales, SaleItems, SaleReturns, SaleReturnItems, Purchases, PurchaseItems,
  PurchaseReturns, PurchaseReturnItems, Payments, PaymentAllocations, Expenses,
  ExpenseCategories, StockAdjustments,
  // Accounting
  Accounts, JournalEntries, JournalLines, CashClosings,
  // Mobile Shop Pro
  UsedPhonePurchases, RepairJobs, RepairParts, RepairStatusLogs, QistPlans, QistSchedule,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => DbMigrations.latestVersion;

  @override
  MigrationStrategy get migration => DbMigrations.strategy(this);
}
