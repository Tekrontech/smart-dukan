import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/coming_soon.dart';
import '../../../core/widgets/empty_state.dart';

/// New Sale (POS) — placeholder. Built fully in Milestone 5 (spec 5.3).
class SaleScreen extends StatelessWidget {
  const SaleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.newSale)),
      body: EmptyState(
        icon: Icons.point_of_sale_rounded,
        title: l.saleEmptyTitle,
        message: l.saleEmptyBody,
        actionLabel: l.addProduct,
        onAction: () => showComingSoon(context),
      ),
    );
  }
}
