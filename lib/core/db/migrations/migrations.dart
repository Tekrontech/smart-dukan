import 'package:drift/drift.dart';

import '../../utils/ids.dart';
import '../app_database.dart';

/// Step-by-step schema migrations (spec Section 6: never drop user data).
///
/// To change the schema:
/// 1. Bump [latestVersion].
/// 2. Add a step `n: (m, db) async { ... }` that upgrades from n-1 to n
///    using `m.addColumn`, `m.createTable` etc. Never drop user columns.
/// 3. Add a migration test from every previous version.
class DbMigrations {
  DbMigrations._();

  static const int latestVersion = 1;

  /// Upgrade steps keyed by the version they upgrade *to*.
  static final Map<int, Future<void> Function(Migrator m, AppDatabase db)> steps = {
    // 2: (m, db) async { await m.addColumn(db.products, db.products.someNewColumn); },
  };

  /// Indexes from spec Section 7 plus a few for common lookups.
  static const List<String> indexes = [
    'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)',
    'CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku)',
    'CREATE INDEX IF NOT EXISTS idx_barcodes_code ON barcodes(code)',
    'CREATE INDEX IF NOT EXISTS idx_imei_units_imei1 ON imei_units(imei1)',
    'CREATE INDEX IF NOT EXISTS idx_imei_units_imei2 ON imei_units(imei2)',
    'CREATE INDEX IF NOT EXISTS idx_parties_name_phone ON parties(name, phone)',
    'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(date)',
    'CREATE INDEX IF NOT EXISTS idx_sales_invoice_no ON sales(invoice_no)',
    'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)',
    'CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON purchase_items(purchase_id)',
    'CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id)',
    'CREATE INDEX IF NOT EXISTS idx_journal_lines_party ON journal_lines(party_id)',
    'CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON journal_lines(entry_id)',
    'CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON journal_entries(date)',
    'CREATE INDEX IF NOT EXISTS idx_journal_entries_source ON journal_entries(source_id)',
    'CREATE INDEX IF NOT EXISTS idx_stock_movements_key ON stock_movements(stock_key)',
    'CREATE INDEX IF NOT EXISTS idx_qist_schedule_due ON qist_schedule(due_date, status)',
    'CREATE INDEX IF NOT EXISTS idx_payment_alloc_doc ON payment_allocations(doc_id)',
    'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(date)',
    'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)',
  ];

  static MigrationStrategy strategy(AppDatabase db) => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final sql in indexes) {
            await db.customStatement(sql);
          }
          await _record(db, latestVersion);
        },
        onUpgrade: (m, from, to) async {
          for (var v = from + 1; v <= to; v++) {
            final step = steps[v];
            if (step == null) throw StateError('Missing migration step to v$v');
            await step(m, db);
            await _record(db, v);
          }
          for (final sql in indexes) {
            await db.customStatement(sql);
          }
        },
      );

  static Future<void> _record(AppDatabase db, int version) async {
    final now = DateTime.now();
    await db.into(db.schemaMigrations).insert(SchemaMigrationsCompanion.insert(
          id: newId(),
          businessId: '',
          createdAt: now,
          updatedAt: now,
          version: version,
          appliedAt: now,
        ));
  }
}
