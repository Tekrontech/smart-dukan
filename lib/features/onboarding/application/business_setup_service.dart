import 'package:drift/drift.dart';

import '../../../core/accounting/system_accounts.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';

/// Creates the shop and its built-in records: chart of accounts, expense
/// categories and base units. Safe to call [seed] again (idempotent).
class BusinessSetupService {
  BusinessSetupService(this.db, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() clock;

  static const Map<String, String> expenseCategoryNames = {
    'rent': 'Rent / Kiraya',
    'bijli': 'Bijli',
    'salary': 'Salary',
    'chai_pani': 'Chai-Pani',
    'transport': 'Transport',
    'other': 'Other',
  };

  Future<Business?> currentBusiness() => (db.select(db.businesses)..limit(1)).getSingleOrNull();

  Future<Business> createBusiness({
    required String name,
    String ownerName = '',
    String? phone,
    String? city,
    BusinessType type = BusinessType.mobileShop,
    DateTime? goLiveDate,
  }) async {
    return db.transaction(() async {
      final existing = await currentBusiness();
      if (existing != null) return existing;
      final now = clock();
      final id = newId();
      await db.into(db.businesses).insert(BusinessesCompanion.insert(
            id: id,
            businessId: id,
            createdAt: now,
            updatedAt: now,
            name: name,
            ownerName: Value(ownerName),
            phone: Value(phone),
            city: Value(city),
            businessType: type,
            goLiveDate: goLiveDate ?? DateTime(now.year, now.month, now.day),
          ));
      await seed(id);
      return (await currentBusiness())!;
    });
  }

  Future<void> seed(String businessId) async {
    final now = clock();
    final existingKeys = (await db.select(db.accounts).get()).map((a) => a.systemKey).toSet();
    for (final a in SysAccount.values) {
      if (existingKeys.contains(a.key)) continue;
      await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: newId(),
            businessId: businessId,
            createdAt: now,
            updatedAt: now,
            code: a.code,
            name: a.name,
            type: a.type,
            systemKey: a.key,
          ));
    }

    final cats = await db.select(db.expenseCategories).get();
    final catKeys = cats.map((c) => c.systemKey).toSet();
    var code = 6001;
    for (final key in builtInExpenseCategories) {
      final accKey = expenseAccountKey(key);
      if (!existingKeys.contains(accKey)) {
        final accId = newId();
        await db.into(db.accounts).insert(AccountsCompanion.insert(
              id: accId,
              businessId: businessId,
              createdAt: now,
              updatedAt: now,
              code: '${code++}',
              name: 'Expense: ${expenseCategoryNames[key]}',
              type: AccountType.expense,
              systemKey: accKey,
            ));
        if (!catKeys.contains(key)) {
          await db.into(db.expenseCategories).insert(ExpenseCategoriesCompanion.insert(
                id: newId(),
                businessId: businessId,
                createdAt: now,
                updatedAt: now,
                name: expenseCategoryNames[key]!,
                systemKey: Value(key),
                accountId: accId,
              ));
        }
      }
    }

    final units = await db.select(db.units).get();
    if (units.isEmpty) {
      final pcs = newId();
      await db.into(db.units).insert(UnitsCompanion.insert(
          id: pcs, businessId: businessId, createdAt: now, updatedAt: now, name: 'Piece', symbol: 'pcs'));
      await db.into(db.units).insert(UnitsCompanion.insert(
          id: newId(),
          businessId: businessId,
          createdAt: now,
          updatedAt: now,
          name: 'Dozen',
          symbol: 'dzn',
          baseUnitId: Value(pcs),
          factor: const Value(12)));
      await db.into(db.units).insert(UnitsCompanion.insert(
          id: newId(),
          businessId: businessId,
          createdAt: now,
          updatedAt: now,
          name: 'Carton',
          symbol: 'ctn',
          baseUnitId: Value(pcs),
          factor: const Value(24)));
      final g = newId();
      await db.into(db.units).insert(UnitsCompanion.insert(
          id: g, businessId: businessId, createdAt: now, updatedAt: now, name: 'Gram', symbol: 'g'));
      await db.into(db.units).insert(UnitsCompanion.insert(
          id: newId(),
          businessId: businessId,
          createdAt: now,
          updatedAt: now,
          name: 'Kilogram',
          symbol: 'kg',
          baseUnitId: Value(g),
          factor: const Value(1000)));
    }
  }

  /// Adds a custom expense category with its own account.
  Future<String> addExpenseCategory(String businessId, String name) async {
    return db.transaction(() async {
      final now = clock();
      final accId = newId();
      final key = 'CUSTOM_${accId.replaceAll('-', '').substring(0, 12).toUpperCase()}';
      await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: accId,
            businessId: businessId,
            createdAt: now,
            updatedAt: now,
            code: '6${(await db.select(db.expenseCategories).get()).length + 100}',
            name: 'Expense: $name',
            type: AccountType.expense,
            systemKey: expenseAccountKey(key),
          ));
      final id = newId();
      await db.into(db.expenseCategories).insert(ExpenseCategoriesCompanion.insert(
            id: id,
            businessId: businessId,
            createdAt: now,
            updatedAt: now,
            name: name,
            accountId: accId,
          ));
      return id;
    });
  }
}
