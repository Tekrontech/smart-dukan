import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/accounting/ledger_queries.dart';
import '../core/accounting/posting.dart';
import '../core/db/app_database.dart';
import '../core/security/key_store.dart';
import '../core/security/license_service.dart';
import '../core/security/photo_vault.dart';
import '../core/security/permissions.dart';
import '../core/settings/settings_repository.dart';
import '../features/cash_closing/application/cash_closing_service.dart';
import '../features/expenses/application/expense_service.dart';
import '../features/onboarding/application/business_setup_service.dart';
import '../features/parties/application/party_service.dart';
import '../features/payments/application/payment_service.dart';
import '../features/pro_mobile/qist/application/qist_service.dart';
import '../features/pro_mobile/repairs/application/repair_service.dart';
import '../features/pro_mobile/used_phones/application/used_phone_service.dart';
import '../features/products/application/product_service.dart';
import '../features/products/data/products_repository.dart';
import '../features/purchases/application/purchase_service.dart';
import '../features/sales/application/sale_service.dart';
import '../features/sales/data/sales_repository.dart';
import '../features/parties/data/parties_repository.dart';
import '../features/settings/application/user_service.dart';

/// The open encrypted database. Always overridden in `bootstrap` (or tests).
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider not overridden'));

/// Keystore-backed secrets. Overridden in `bootstrap` (or tests).
final keyStoreProvider = Provider<SecureKeyStore>((ref) => MemoryKeyStore());

/// App-private data folder (database, encrypted photos, logo).
final appDirProvider = Provider<Directory>((ref) => Directory.systemTemp);

final photoVaultProvider = Provider<PhotoVault>((ref) => PhotoVault(
      dir: Directory(p.join(ref.watch(appDirProvider).path, 'photos')),
      keyStore: ref.watch(keyStoreProvider),
    ));

/// Values read once at start-up (install id, whether secure storage and the
/// DB agree ...). Overridden in `bootstrap`.
final startupInfoProvider = Provider<StartupInfo>((ref) => const StartupInfo(installId: '00000000-0000-4000-8000-000000000000'));

class StartupInfo {
  const StartupInfo({required this.installId, this.installIdMismatch = false});

  final String installId;

  /// Secure storage and the database disagree about the install id (spec 2
  /// licence lifecycle): Pro needs re-activation, data stays readable.
  final bool installIdMismatch;
}

/// Who is using the app right now.
class Session {
  const Session({this.business, this.user, this.locked = true});

  final Business? business;
  final AppUser? user;
  final bool locked;

  bool get onboarded => business != null;
  Permissions get can => Permissions(user?.role ?? UserRole.cashier);

  Session copyWith({Business? business, AppUser? user, bool? locked, bool clearUser = false}) => Session(
        business: business ?? this.business,
        user: clearUser ? null : (user ?? this.user),
        locked: locked ?? this.locked,
      );
}

/// Initial session, loaded in bootstrap.
final initialSessionProvider = Provider<Session>((ref) => const Session());

class SessionNotifier extends Notifier<Session> {
  @override
  Session build() => ref.read(initialSessionProvider);

  Future<void> reloadBusiness() async {
    final db = ref.read(databaseProvider);
    final b = await BusinessSetupService(db).currentBusiness();
    state = state.copyWith(business: b);
  }

  Future<void> unlock(AppUser user) async {
    final db = ref.read(databaseProvider);
    await SettingsRepository(db).set(SettingKeys.lastUserId, user.id);
    await UserService(db, businessId: state.business?.id ?? '', actorId: user.id).recordLogin(user.id);
    state = state.copyWith(user: user, locked: false);
  }

  void lock() => state = state.copyWith(locked: true);

  void setUser(AppUser user) => state = state.copyWith(user: user);
}

final sessionProvider = NotifierProvider<SessionNotifier, Session>(SessionNotifier.new);

final permissionsProvider = Provider<Permissions>((ref) => ref.watch(sessionProvider).can);

final ctxProvider = Provider<BusinessCtx>((ref) {
  final s = ref.watch(sessionProvider);
  return BusinessCtx(businessId: s.business?.id ?? '', userId: s.user?.id);
});

final settingsRepoProvider = Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));
final ledgerProvider = Provider((ref) => LedgerQueries(ref.watch(databaseProvider)));

final productServiceProvider = Provider((ref) => ProductService(ref.watch(databaseProvider), ref.watch(ctxProvider)));
final partyServiceProvider = Provider((ref) => PartyService(ref.watch(databaseProvider), ref.watch(ctxProvider)));
final saleServiceProvider = Provider((ref) => SaleService(ref.watch(databaseProvider), ref.watch(ctxProvider)));
final purchaseServiceProvider = Provider((ref) => PurchaseService(ref.watch(databaseProvider), ref.watch(ctxProvider)));
final paymentServiceProvider = Provider((ref) => PaymentService(ref.watch(databaseProvider), ref.watch(ctxProvider)));
final expenseServiceProvider = Provider((ref) => ExpenseService(ref.watch(databaseProvider), ref.watch(ctxProvider)));
final cashClosingServiceProvider =
    Provider((ref) => CashClosingService(ref.watch(databaseProvider), ref.watch(ctxProvider)));
final repairServiceProvider = Provider((ref) => RepairService(ref.watch(databaseProvider), ref.watch(ctxProvider)));
final qistServiceProvider = Provider((ref) => QistService(ref.watch(databaseProvider), ref.watch(ctxProvider)));
final usedPhoneServiceProvider =
    Provider((ref) => UsedPhoneService(ref.watch(databaseProvider), ref.watch(ctxProvider)));
final userServiceProvider = Provider((ref) {
  final s = ref.watch(sessionProvider);
  return UserService(ref.watch(databaseProvider), businessId: s.business?.id ?? '', actorId: s.user?.id);
});

final licenseServiceProvider = Provider((ref) => LicenseService(
      db: ref.watch(databaseProvider),
      keyStore: ref.watch(keyStoreProvider),
      installId: ref.watch(startupInfoProvider).installId,
    ));

/// Whether Mobile Shop Pro is unlocked. Invalidate after activation.
final proActiveProvider = FutureProvider<bool>((ref) => ref.watch(licenseServiceProvider).isActive(Packs.mobilePro));

final productsRepoProvider = Provider((ref) => ProductsRepository(ref.watch(databaseProvider)));
final salesRepoProvider = Provider((ref) => SalesRepository(ref.watch(databaseProvider)));
final partiesRepoProvider = Provider((ref) => PartiesRepository(ref.watch(databaseProvider)));
