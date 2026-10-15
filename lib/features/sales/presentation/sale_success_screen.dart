import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/sales_repository.dart';
import 'receipt_actions.dart';

/// Success screen after a sale (spec 4 Motion, 5.3 step 8): big tick,
/// amount, Share / Print / New Sale, and a 5-second Undo that creates a
/// reversal (never a delete).
class SaleSuccessScreen extends ConsumerStatefulWidget {
  const SaleSuccessScreen({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<SaleSuccessScreen> createState() => _SaleSuccessScreenState();
}

class _SaleSuccessScreenState extends ConsumerState<SaleSuccessScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _tick =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450))..forward();
  SaleView? _view;
  bool _undone = false;

  @override
  void initState() {
    super.initState();
    ref.read(salesRepoProvider).load(widget.saleId).then((v) {
      if (!mounted) return;
      setState(() => _view = v);
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerUndo());
    });
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  void _offerUndo() {
    final l = context.l10n;
    // Undo right after saving is the cashier correcting a mis-tap, so it
    // needs no owner PIN (DECISIONS.md D-024); it is still a reversal.
    showMessage(context, l.saleSaved, actionLabel: l.undo, duration: const Duration(seconds: 5), onAction: () async {
      final ok = await guard(context, () => ref.read(saleServiceProvider).reverseSale(widget.saleId));
      if (ok != null && mounted) {
        setState(() => _undone = true);
        showMessage(context, l.saleUndone);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final v = _view;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              ScaleTransition(
                scale: CurvedAnimation(parent: _tick, curve: Curves.easeOutBack),
                child: Icon(_undone ? Icons.undo_rounded : Icons.check_circle_rounded,
                    size: 112, color: _undone ? c.warning : c.success),
              ),
              const SizedBox(height: AppSpacing.md),
              if (v != null) ...[
                Ltr(Text(Fmt.money(v.sale.total), textAlign: TextAlign.center, style: theme.textTheme.displayMedium)),
                Text(l.invoiceNo(v.sale.invoiceNo), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                if (v.party != null) Text(v.party!.name, textAlign: TextAlign.center),
                if (_undone) Text(l.saleUndone, textAlign: TextAlign.center, style: TextStyle(color: c.warning)),
              ],
              const Spacer(),
              if (v != null && !_undone) ...[
                Row(children: [
                  Expanded(
                    child: PrimaryButton(
                      key: const Key('success_share'),
                      label: l.share,
                      icon: Icons.share_rounded,
                      outlined: true,
                      onPressed: () => shareReceipt(context, ref, v.sale.id, v.sale.invoiceNo),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: PrimaryButton(
                      label: l.print,
                      icon: Icons.print_rounded,
                      outlined: true,
                      onPressed: () => printReceipt(context, ref, v.sale.id),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.sm),
              ],
              PrimaryButton(
                key: const Key('success_new_sale'),
                label: l.newSaleAgain,
                icon: Icons.add_rounded,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  context.go(Routes.sale);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
