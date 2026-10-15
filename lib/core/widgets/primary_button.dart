import 'package:flutter/material.dart';

/// Full-width, 56-high primary button with a leading icon (spec Section 4).
///
/// While [loading] is true the button is disabled, which prevents double
/// taps from creating duplicate documents.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final Widget leading = loading
        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Icon(icon ?? Icons.check_rounded);

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null || loading) ...[leading, const SizedBox(width: 8)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );

    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton(onPressed: enabled ? onPressed : null, child: content)
          : FilledButton(onPressed: enabled ? onPressed : null, child: content),
    );
  }
}
