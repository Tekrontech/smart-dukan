import 'package:drift/drift.dart' show OrderingTerm, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/pin_gate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/amount_keypad.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/labels.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/primary_button.dart';
import '../../onboarding/application/business_setup_service.dart';

String expenseCategoryLabel(BuildContext context, String? systemKey, String name) {
  final l = context.l10n;
  return switch (systemKey) {
    'rent' => l.catRent,
    'bijli' => l.catBijli,
    'salary' => l.catSalary,
    'chai_pani' => l.catChai,
    'transport' => l.catTransport,
    'other' => l.catOther,
    _ => name,
  };
}

/// New expense (spec 5.7): category, amount, method, note, receipt photo.
class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({super.key});

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen> {
  String? _cat;
  Money _amount = Money.zero;
  PaymentMethod _method = PaymentMethod.cash;
  final _note = TextEditingController();
  String? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_cat == null || !_amount.isPositive) return;
    setState(() => _busy = true);
    final ok = await guard(context, () => ref.read(expenseServiceProvider).create(
          categoryId: _cat!,
          amount: _amount,
          method: _method,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          photoPath: _photo,
        ));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok != null) {
      savedHaptic();
      showMessage(context, context.l10n.expenseSaved);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final db = ref.watch(databaseProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.newExpense)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(l.expenseCategory, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<List<ExpenseCategory>>(
            stream: (db.select(db.expenseCategories)..where((x) => x.isActive.equals(true))).watch(),
            builder: (context, snap) {
              final cats = snap.data ?? const <ExpenseCategory>[];
              _cat ??= cats.where((x) => x.systemKey == 'chai_pani').firstOrNull?.id;
              return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                for (final cat in cats)
                  ChoiceChip(
                    label: Text(expenseCategoryLabel(context, cat.systemKey, cat.name)),
                    selected: _cat == cat.id,
                    onSelected: (_) => setState(() => _cat = cat.id),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(l.addCategory),
                  onPressed: () async {
                    final ctrl = TextEditingController();
                    final name = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(l.addCategory),
                        content: TextField(controller: ctrl, autofocus: true),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
                          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(l.add)),
                        ],
                      ),
                    );
                    if (name == null || name.isEmpty) return;
                    final id = await BusinessSetupService(db).addExpenseCategory(ref.read(sessionProvider).business!.id, name);
                    setState(() => _cat = id);
                  },
                ),
              ]);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            key: const Key('expense_amount'),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            onTap: () async {
              final m = await AmountKeypad.show(context, title: l.amount, doneLabel: l.done, initial: _amount);
              if (m != null) setState(() => _amount = m);
            },
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(AppSpacing.cardRadius)),
              child: Column(children: [
                Text(l.amount, style: theme.textTheme.labelLarge),
                Ltr(Text(Fmt.money(_amount), style: theme.textTheme.displayMedium?.copyWith(color: c.danger))),
              ]),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.sm, children: [
            for (final m in PaymentMethod.values)
              ChoiceChip(label: Text(context.methodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
          ]),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _note, decoration: InputDecoration(labelText: l.note)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_photo == null ? Icons.add_a_photo_outlined : Icons.check_circle_rounded),
            title: Text(l.receiptPhoto),
            onTap: () async {
              final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 70);
              if (x == null) return;
              final name = await ref.read(photoVaultProvider).save(await x.readAsBytes());
              setState(() => _photo = name);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            key: const Key('expense_save'),
            label: l.save,
            icon: Icons.check_rounded,
            loading: _busy,
            onPressed: _cat != null && _amount.isPositive ? _save : null,
          ),
        ],
      ),
    );
  }
}

/// Expense list with reversal (owner PIN).
class ExpensesListScreen extends ConsumerWidget {
  const ExpensesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.expenses)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_expense',
        onPressed: () => context.push(Routes.expenseNew),
        icon: const Icon(Icons.add),
        label: Text(l.newExpense),
      ),
      body: StreamBuilder<List<ExpenseCategory>>(
        stream: db.select(db.expenseCategories).watch(),
        builder: (context, cs) {
          final cats = {for (final c in cs.data ?? const <ExpenseCategory>[]) c.id: c};
          return StreamBuilder<List<Expense>>(
            stream: (db.select(db.expenses)
                  ..where((e) => e.status.equalsValue(DocStatus.reversal).not())
                  ..orderBy([(e) => OrderingTerm.desc(e.date)])
                  ..limit(200))
                .watch(),
            builder: (context, snap) {
              final rows = snap.data ?? const <Expense>[];
              if (rows.isEmpty) return EmptyState(icon: Icons.payments_outlined, title: l.noExpenses, message: '');
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final e = rows[i];
                  final reversed = e.status == DocStatus.reversed;
                  final cat = cats[e.categoryId];
                  return ListTile(
                    title: Text(cat == null ? '-' : expenseCategoryLabel(context, cat.systemKey, cat.name),
                        style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null)),
                    subtitle: Text('${Fmt.dateTime(e.date)} • ${context.methodLabel(e.method)}${e.note == null ? '' : ' • ${e.note}'}'),
                    trailing: Ltr(Text(Fmt.money(e.amount))),
                    onLongPress: reversed
                        ? null
                        : () async {
                            if (!await ref.read(pinGateProvider).requireOwner(context, reason: l.reverseConfirmBody)) return;
                            if (!context.mounted) return;
                            final r = await guard(context, () => ref.read(expenseServiceProvider).reverse(e.id));
                            if (r != null && context.mounted) showMessage(context, l.reversed);
                          },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
