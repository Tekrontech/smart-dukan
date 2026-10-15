import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/amount_keypad.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/cash_closing_service.dart';

final _summaryProvider = FutureProvider.autoDispose<CashDaySummary>((ref) => ref.watch(cashClosingServiceProvider).summary());

/// Galla Band — cash closing (spec 5.8): opening, cash in/out, expected,
/// counted with note helper, difference posted as cash over/short.
class GallaScreen extends ConsumerStatefulWidget {
  const GallaScreen({super.key});

  @override
  ConsumerState<GallaScreen> createState() => _GallaScreenState();
}

class _GallaScreenState extends ConsumerState<GallaScreen> {
  final Map<int, int> _notes = {for (final d in cashDenominations) d: 0};
  Money? _typed;
  bool _busy = false;

  Money get _counted => _typed ?? Money.rupees(_notes.entries.fold(0, (a, e) => a + e.key * e.value));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(_summaryProvider).value;
    if (s == null) return Scaffold(appBar: AppBar(title: Text(l.gallaBand)), body: const Center(child: CircularProgressIndicator()));
    final closed = s.closing;
    final diff = _counted - s.expected;

    Widget row(String k, Money v, {Color? color, bool big = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(k, style: big ? theme.textTheme.titleLarge : theme.textTheme.bodyLarge)),
            Ltr(Text(Fmt.money(v), style: (big ? theme.textTheme.titleLarge : theme.textTheme.bodyLarge)?.copyWith(color: color))),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.gallaBand)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(Fmt.date(s.day), style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(children: [
                row(l.openingCash, s.opening),
                row('+ ${l.cashSales}', s.cashSales, color: c.success),
                row('+ ${l.cashReceived}', s.cashReceived, color: c.success),
                row('− ${l.cashPaid}', s.cashPaid, color: c.danger),
                row('− ${l.cashExpenses}', s.expenses, color: c.danger),
                if (!s.other.isZero) row('± ${l.otherCash}', s.other),
                const Divider(),
                row(l.expectedCash, s.expected, big: true),
              ]),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (closed != null)
            Card(
              color: c.primaryContainer,
              child: ListTile(
                leading: Icon(Icons.lock_rounded, color: c.primary),
                title: Text(l.gallaClosed),
                subtitle: Ltr(Text(l.gallaAlreadyClosed(Fmt.money(closed.countedCash), Fmt.money(closed.difference)))),
              ),
            )
          else ...[
            Text(l.countNotes, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final d in cashDenominations)
              Row(children: [
                SizedBox(width: 88, child: Ltr(Text('Rs ${Fmt.qty(d)}', style: theme.textTheme.titleSmall))),
                IconButton(
                  onPressed: _notes[d]! > 0 ? () => setState(() => (_notes[d] = _notes[d]! - 1, _typed = null)) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(width: 40, child: Ltr(Text('${_notes[d]}', textAlign: TextAlign.center, style: theme.textTheme.titleMedium))),
                IconButton(
                  key: Key('note_plus_$d'),
                  onPressed: () => setState(() => (_notes[d] = _notes[d]! + 1, _typed = null)),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                Expanded(child: Ltr(Text(Fmt.money(Money.rupees(d * _notes[d]!)), textAlign: TextAlign.end))),
              ]),
            const Divider(),
            InkWell(
              onTap: () async {
                final m = await AmountKeypad.show(context, title: l.countedCash, doneLabel: l.done, initial: _counted);
                if (m != null) setState(() => _typed = m);
              },
              child: row(l.countedCash, _counted, big: true),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                diff.isZero ? l.cashExact : (diff.isNegative ? l.cashShort(Fmt.money(-diff)) : l.cashOver(Fmt.money(diff))),
                style: theme.textTheme.titleMedium?.copyWith(color: diff.isZero ? c.success : (diff.isNegative ? c.danger : c.warning)),
              ),
            ),
            PrimaryButton(
              key: const Key('close_galla'),
              label: l.closeGalla,
              icon: Icons.lock_clock_rounded,
              loading: _busy,
              onPressed: () async {
                setState(() => _busy = true);
                final ok = await guard(context, () => ref.read(cashClosingServiceProvider).close(
                      counted: _counted,
                      denominations: _typed == null ? Map.of(_notes) : const {},
                    ));
                if (!mounted) return;
                setState(() => _busy = false);
                if (ok != null) {
                  savedHaptic();
                  if (context.mounted) showMessage(context, l.gallaClosed);
                  ref.invalidate(_summaryProvider);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
