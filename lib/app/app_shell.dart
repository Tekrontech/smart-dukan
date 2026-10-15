import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';

/// Scaffold with the 5-tab bottom navigation and the large centre
/// "+ Nayi Sale" button (spec Section 4).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const int saleTab = 1;

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final onSaleTab = shell.currentIndex == saleTab;

    return Scaffold(
      body: shell,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: onSaleTab
          ? null
          : FloatingActionButton.extended(
              key: const Key('fab_new_sale'),
              onPressed: () => _go(saleTab),
              icon: const Icon(Icons.add_rounded, size: 28),
              label: Text(l.newSale),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: l.tabHome),
          NavigationDestination(icon: const Icon(Icons.point_of_sale_outlined), selectedIcon: const Icon(Icons.point_of_sale_rounded), label: l.tabSale),
          NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book_rounded), label: l.tabKhata),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2_rounded), label: l.tabStock),
          NavigationDestination(icon: const Icon(Icons.more_horiz_rounded), selectedIcon: const Icon(Icons.more_horiz_rounded), label: l.tabMore),
        ],
      ),
    );
  }
}
