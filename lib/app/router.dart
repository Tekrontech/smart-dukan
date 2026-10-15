import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/db/app_database.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/cash_closing/presentation/galla_screen.dart';
import '../features/dashboard/presentation/home_screen.dart';
import '../features/expenses/presentation/expense_screens.dart';
import '../features/license/presentation/license_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/parties/presentation/khata_screen.dart';
import '../features/parties/presentation/party_detail_screen.dart';
import '../features/parties/presentation/party_form_screen.dart';
import '../features/payments/presentation/payment_screen.dart';
import '../features/pro_mobile/imei/presentation/imei_search_screen.dart';
import '../features/pro_mobile/qist/presentation/qist_screens.dart';
import '../features/pro_mobile/repairs/presentation/repair_screens.dart';
import '../features/pro_mobile/used_phones/presentation/used_phone_screens.dart';
import '../features/products/presentation/import_screen.dart';
import '../features/products/presentation/product_detail_screen.dart';
import '../features/products/presentation/product_form_screen.dart';
import '../features/products/presentation/stock_screen.dart';
import '../features/purchases/presentation/purchase_detail_screen.dart';
import '../features/purchases/presentation/purchase_screen.dart';
import '../features/reports/application/reports_service.dart';
import '../features/reports/presentation/reports_screens.dart';
import '../features/sales/presentation/sale_detail_screen.dart';
import '../features/sales/presentation/sale_return_screen.dart';
import '../features/sales/presentation/sale_screen.dart';
import '../features/sales/presentation/sale_success_screen.dart';
import '../features/sales/presentation/sales_list_screen.dart';
import '../features/settings/presentation/info_screens.dart';
import '../features/settings/presentation/lock_screen.dart';
import '../features/settings/presentation/more_screen.dart';
import '../features/settings/presentation/security_screen.dart';
import '../features/settings/presentation/shop_profile_screen.dart';
import '../features/settings/presentation/staff_screen.dart';
import 'app_shell.dart';
import 'providers.dart';

/// Route paths. Use these, never string literals in widgets.
class Routes {
  Routes._();

  static const onboarding = '/onboarding';
  static const lock = '/lock';
  static const home = '/home';
  static const sale = '/sale';
  static const khata = '/khata';
  static const stock = '/stock';
  static const more = '/more';

  static String saleDone(String id) => '/sales/$id/done';
  static String saleDetail(String id) => '/sales/$id';
  static String saleReturn(String id) => '/sales/$id/return';
  static const salesList = '/sales';

  static const productNew = '/products/new';
  static const productImport = '/products/import';
  static String product(String id) => '/products/$id';
  static String productEdit(String id) => '/products/$id/edit';

  static const purchaseNew = '/purchases/new';
  static const purchasesList = '/purchases';
  static String purchaseDetail(String id) => '/purchases/$id';

  static String partyNew(PartyType type) => '/parties/new?type=${type.name}';
  static String party(String id) => '/parties/$id';
  static String partyEdit(String id) => '/parties/$id/edit';

  static String paymentNew({required bool incoming, String? partyId}) =>
      '/payments/new?dir=${incoming ? 'in' : 'out'}${partyId == null ? '' : '&party=$partyId'}';

  static const expenseNew = '/expenses/new';
  static const expensesList = '/expenses';
  static const galla = '/galla';
  static const reports = '/reports';
  static String report(String kind) => '/reports/$kind';

  static const imeiSearch = '/pro/imei';
  static const usedPhoneList = '/pro/used';
  static const usedPhoneNew = '/pro/used/new';
  static String usedPhone(String id) => '/pro/used/$id';
  static const repairs = '/pro/repairs';
  static const repairNew = '/pro/repairs/new';
  static String repair(String id) => '/pro/repairs/$id';
  static const qistList = '/pro/qist';
  static String qist(String id) => '/pro/qist/$id';

  static const shopProfile = '/settings/profile';
  static const security = '/settings/security';
  static const staff = '/settings/staff';
  static const backup = '/settings/backup';
  static const importExport = '/settings/import';
  static const license = '/settings/license';
  static const healthCheck = '/settings/health';
  static const info = '/settings/info';

  /// Deep link for licence activation (spec Section 2):
  /// smartdukan://activate?c=<base64url>.
  static const activate = '/activate';
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// A code from `smartdukan://activate?c=` that arrived while locked; shown
/// on the licence screen right after unlock.
String? pendingActivationCode;

GoRouter buildRouter(Ref ref, Listenable refresh) {
  GoRoute page(String path, Widget Function(GoRouterState s) build) =>
      GoRoute(path: path, parentNavigatorKey: rootNavigatorKey, builder: (_, s) => build(s));

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final s = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      // smartdukan://activate?c=... may arrive with the scheme's host as path.
      if (state.uri.queryParameters['c'] != null && (loc == Routes.activate || state.uri.host == 'activate')) {
        pendingActivationCode = state.uri.queryParameters['c'];
      }
      if (!s.onboarded) return loc == Routes.onboarding ? null : Routes.onboarding;
      if (s.locked) return loc == Routes.lock ? null : Routes.lock;
      if (loc == Routes.onboarding || loc == Routes.lock) {
        return pendingActivationCode != null ? Routes.license : Routes.home;
      }
      if (loc == Routes.activate || state.uri.host == 'activate') return Routes.license;
      return null;
    },
    routes: [
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: Routes.lock, builder: (_, _) => const LockScreen()),
      GoRoute(path: Routes.activate, builder: (_, _) => const SizedBox()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.sale, builder: (_, _) => const SaleScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.khata, builder: (_, _) => const KhataScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.stock, builder: (_, _) => const StockScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.more, builder: (_, _) => const MoreScreen())]),
        ],
      ),
      // Sales
      page(Routes.salesList, (_) => const SalesListScreen()),
      page('/sales/:id/done', (s) => SaleSuccessScreen(saleId: s.pathParameters['id']!)),
      page('/sales/:id/return', (s) => SaleReturnScreen(saleId: s.pathParameters['id']!)),
      page('/sales/:id', (s) => SaleDetailScreen(saleId: s.pathParameters['id']!)),
      // Products
      page(Routes.productNew, (_) => const ProductFormScreen()),
      page(Routes.productImport, (_) => const ImportScreen()),
      page('/products/:id/edit', (s) => ProductFormScreen(productId: s.pathParameters['id'])),
      page('/products/:id', (s) => ProductDetailScreen(productId: s.pathParameters['id']!)),
      // Purchases
      page(Routes.purchaseNew, (_) => const PurchaseScreen()),
      page(Routes.purchasesList, (_) => const PurchasesListScreen()),
      page('/purchases/:id', (s) => PurchaseDetailScreen(purchaseId: s.pathParameters['id']!)),
      // Parties
      page('/parties/new', (s) => PartyFormScreen(type: PartyType.values.asNameMap()[s.uri.queryParameters['type']] ?? PartyType.customer)),
      page('/parties/:id/edit', (s) => PartyFormScreen(partyId: s.pathParameters['id'])),
      page('/parties/:id', (s) => PartyDetailScreen(partyId: s.pathParameters['id']!)),
      // Money
      page('/payments/new', (s) => PaymentScreen(incoming: s.uri.queryParameters['dir'] != 'out', partyId: s.uri.queryParameters['party'])),
      page(Routes.expenseNew, (_) => const ExpenseScreen()),
      page(Routes.expensesList, (_) => const ExpensesListScreen()),
      page(Routes.galla, (_) => const GallaScreen()),
      page(Routes.reports, (_) => const ReportsScreen()),
      page('/reports/:kind', (s) => ReportViewScreen(kind: ReportKind.values.asNameMap()[s.pathParameters['kind']] ?? ReportKind.daily)),
      // Mobile Shop Pro
      page(Routes.imeiSearch, (s) => ImeiSearchScreen(initial: s.uri.queryParameters['q'])),
      page(Routes.usedPhoneList, (_) => const UsedPhonesListScreen()),
      page(Routes.usedPhoneNew, (_) => const UsedPhoneFormScreen()),
      page('/pro/used/:id', (s) => UsedPhoneDetailScreen(id: s.pathParameters['id']!)),
      page(Routes.repairs, (_) => const RepairsListScreen()),
      page(Routes.repairNew, (_) => const RepairFormScreen()),
      page('/pro/repairs/:id', (s) => RepairDetailScreen(jobId: s.pathParameters['id']!)),
      page(Routes.qistList, (_) => const QistListScreen()),
      page('/pro/qist/:id', (s) => QistDetailScreen(planId: s.pathParameters['id']!)),
      // Settings
      page(Routes.shopProfile, (_) => const ShopProfileScreen()),
      page(Routes.security, (_) => const SecurityScreen()),
      page(Routes.staff, (_) => const StaffScreen()),
      page(Routes.backup, (_) => const BackupScreen()),
      page(Routes.importExport, (_) => const ImportScreen()),
      page(Routes.license, (_) {
        final code = pendingActivationCode;
        pendingActivationCode = null;
        return LicenseScreen(initialCode: code);
      }),
      page(Routes.healthCheck, (_) => const HealthCheckScreen()),
      page('${Routes.info}/:page', (s) => InfoScreen(page: s.pathParameters['page']!)),
    ],
  );
}
