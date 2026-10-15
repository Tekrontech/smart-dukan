import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../money/money.dart';
import '../money/money_format.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'ltr.dart';
import 'primary_button.dart';

/// Large-key numeric keypad sheet for entering amounts (spec Section 4).
///
/// Has a "000" key for fast entry of round amounts and a "." key for paisa.
/// Returns the entered [Money], or null if dismissed.
class AmountKeypad extends StatefulWidget {
  const AmountKeypad({super.key, required this.title, required this.doneLabel, this.initial});

  final String title;
  final String doneLabel;
  final Money? initial;

  /// Maximum whole-rupee digits (999,999,999 rupees) to avoid overflow and
  /// fat-finger errors.
  static const int maxRupeeDigits = 9;

  static Future<Money?> show(BuildContext context, {required String title, required String doneLabel, Money? initial}) {
    return showModalBottomSheet<Money>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AmountKeypad(title: title, doneLabel: doneLabel, initial: initial),
    );
  }

  /// Pure input logic, exposed for tests.
  static String applyKey(String input, String key) {
    if (key == '⌫') return input.isEmpty ? input : input.substring(0, input.length - 1);
    if (key == 'C') return '';

    final hasDot = input.contains('.');
    if (key == '.') {
      if (hasDot) return input;
      return input.isEmpty ? '0.' : '$input.';
    }

    var next = input + key;
    if (hasDot) {
      final decimals = next.split('.')[1];
      if (decimals.length > 2) return input;
    } else {
      next = next.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (next.length > maxRupeeDigits) return input;
    }
    return next;
  }

  @override
  State<AmountKeypad> createState() => _AmountKeypadState();
}

class _AmountKeypadState extends State<AmountKeypad> {
  late String _input;

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    if (m == null || m.isZero) {
      _input = '';
    } else {
      _input = MoneyFormat.format(m, symbol: false).replaceAll(',', '');
    }
  }

  Money get _value => MoneyFormat.parse(_input.isEmpty ? '0' : _input) ?? Money.zero;

  void _press(String key) {
    HapticFeedback.selectionClick();
    setState(() => _input = AmountKeypad.applyKey(_input, key));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '000', '0', '⌫'];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(color: c.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Ltr(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: c.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _input.endsWith('.') ? '${MoneyFormat.format(_value)}.' : MoneyFormat.format(_value),
                    style: theme.textTheme.displayMedium?.copyWith(color: c.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Ltr(
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 2.0,
                children: [
                  for (final k in keys)
                    _Key(
                      label: k,
                      onTap: () => _press(k),
                      onLongPress: k == '⌫' ? () => _press('C') : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: OutlinedButton(onPressed: () => _press('.'), child: const Text('.')),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: widget.doneLabel,
                    icon: Icons.check_rounded,
                    onPressed: () => Navigator.of(context).pop(_value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap, this.onLongPress});

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.background,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Center(
          child: label == '⌫'
              ? Icon(Icons.backspace_outlined, color: c.textPrimary)
              : Text(label, style: Theme.of(context).textTheme.headlineMedium),
        ),
      ),
    );
  }
}
