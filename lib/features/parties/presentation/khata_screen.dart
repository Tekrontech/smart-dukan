import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/coming_soon.dart';
import '../../../core/widgets/empty_state.dart';

/// Khata — customers and suppliers. Placeholder; built in Milestone 6
/// (spec 5.6).
class KhataScreen extends StatelessWidget {
  const KhataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.tabKhata),
          bottom: TabBar(tabs: [Tab(text: l.customers), Tab(text: l.suppliers)]),
        ),
        body: TabBarView(
          children: [
            EmptyState(
              icon: Icons.people_outline_rounded,
              title: l.khataEmptyTitle,
              message: l.khataEmptyBody,
              actionLabel: l.addCustomer,
              actionIcon: Icons.person_add_alt_1_rounded,
              onAction: () => showComingSoon(context),
            ),
            EmptyState(
              icon: Icons.local_shipping_outlined,
              title: l.khataEmptyTitle,
              message: l.khataEmptyBody,
            ),
          ],
        ),
      ),
    );
  }
}
