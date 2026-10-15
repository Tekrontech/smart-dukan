import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../money/money.dart';
import '../money/money_format.dart';
import 'ltr.dart';

/// Rupee input for forms (integer paisa underneath, never double).
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.required = false,
    this.allowZero = true,
    this.onChanged,
    this.helper,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final bool allowZero;
  final ValueChanged<Money?>? onChanged;
  final String? helper;
  final bool enabled;

  static Money? read(TextEditingController c) => c.text.trim().isEmpty ? Money.zero : MoneyFormat.parse(c.text);

  static String text(Money m) => m.isZero ? '' : MoneyFormat.format(m, symbol: false, urduDigits: false).replaceAll(',', '');

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Ltr(
      TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(labelText: label, prefixText: 'Rs ', helperText: helper),
        onChanged: onChanged == null ? null : (_) => onChanged!(read(controller)),
        validator: (v) {
          final t = v?.trim() ?? '';
          if (t.isEmpty) return required ? l.fieldRequired : null;
          final m = MoneyFormat.parse(t);
          if (m == null || m.isNegative) return l.invalidNumber;
          if (!allowZero && m.isZero) return l.fieldRequired;
          return null;
        },
      ),
    );
  }
}

/// Whole-number input (quantities).
class IntField extends StatelessWidget {
  const IntField({super.key, required this.controller, required this.label, this.required = false, this.min = 0, this.onChanged});

  final TextEditingController controller;
  final String label;
  final bool required;
  final int min;
  final ValueChanged<int?>? onChanged;

  static int read(TextEditingController c, {int fallback = 0}) => int.tryParse(c.text.trim()) ?? fallback;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Ltr(
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged == null ? null : (v) => onChanged!(int.tryParse(v)),
        validator: (v) {
          final t = v?.trim() ?? '';
          if (t.isEmpty) return required ? l.fieldRequired : null;
          final n = int.tryParse(t);
          if (n == null || n < min) return l.invalidNumber;
          return null;
        },
      ),
    );
  }
}
