import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/home_screen.dart';
import '../features/parties/presentation/khata_screen.dart';
import '../features/products/presentation/stock_screen.dart';
import '../features/sales/presentation/sale_screen.dart';
import '../features/settings/presentation/more_screen.dart';
import 'app_shell.dart';

/// Route paths. Use these constants, never string literals in widgets.
class Routes {
  Routes._();

  static const home = '/home';
  static const sale = '/sale';
  static const khata = '/khata';
  static const stock = '/stock';
  static const more = '/more';

  /// Deep link for licence activation (spec Section 2):
  /// smartdukan://activate?c=<base64url>. Wired up in Milestone 9.
  static const activate = '/activate';
}

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter buildRouter() => GoRouter(
      navigatorKey: _rootKey,
      initialLocation: Routes.home,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (context, state) => const HomeScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: Routes.sale, builder: (context, state) => const SaleScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: Routes.khata, builder: (context, state) => const KhataScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: Routes.stock, builder: (context, state) => const StockScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: Routes.more, builder: (context, state) => const MoreScreen())]),
          ],
        ),
      ],
    );
