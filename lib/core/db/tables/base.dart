import 'package:drift/drift.dart';

/// Columns every table carries (spec Section 6/7): UUID v7 `id`,
/// `business_id`, `created_at`, `updated_at`, `created_by`.
///
/// Money columns are INTEGER paisa mapped to `Money` with `MoneyConverter`;
/// quantities are INTEGER in the smallest unit.
mixin BaseColumns on Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get createdBy => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
