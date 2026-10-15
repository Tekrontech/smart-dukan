import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/coming_soon.dart';
import '../../../core/widgets/empty_state.dart';

/// Stock (products) — placeholder. Built in Milestone 4 (spec 5.5).
class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.tabStock)),
      body: EmptyState(
        icon: Icons.inventory_2_outlined,
        title: l.stockEmptyTitle,
        message: l.stockEmptyBody,
        actionLabel: l.addProduct,
        onAction: () => showComingSoon(context),
      ),
    );
  }
}
