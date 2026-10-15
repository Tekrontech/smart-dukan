import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'ltr.dart';

/// Big-key PIN entry: dots + numeric keypad. Calls [onCompleted] once
/// [length] digits are entered; the parent decides what happens next and
/// can call [PinPadState.clear] / [PinPadState.shake].
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onCompleted,
    this.length = 4,
    this.error,
    this.busy = false,
    this.extraKey,
  });

  final ValueChanged<String> onCompleted;
  final int length;
  final String? error;
  final bool busy;

  /// Optional bottom-left key (e.g. fingerprint).
  final Widget? extraKey;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';

  void clear() => setState(() => _pin = '');

  void _press(String k) {
    if (widget.busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < widget.length) {
        _pin += k;
      }
    });
    if (_pin.length == widget.length) {
      final value = _pin;
      Future.microtask(() => widget.onCompleted(value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    return Ltr(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++)
                AnimatedContainer(
                  duration: AppSpacing.motion,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? c.primary : Colors.transparent,
                    border: Border.all(color: widget.error != null ? c.danger : c.primary, width: 2),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 32,
            child: Center(
              child: widget.busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.error ?? '', style: theme.textTheme.bodyMedium?.copyWith(color: c.danger)),
            ),
          ),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            _row(row.map((k) => _Key(label: k, onTap: () => _press(k))).toList()),
          _row([
            widget.extraKey ?? const SizedBox(),
            _Key(label: '0', onTap: () => _press('0')),
            _Key(icon: Icons.backspace_outlined, onTap: () => _press('⌫'), key: const Key('pin_backspace')),
          ]),
        ],
      ),
    );
  }

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [for (final c in children) SizedBox(width: 92, height: 64, child: c)],
        ),
      );
}

class _Key extends StatelessWidget {
  const _Key({super.key, this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          key: label == null ? null : Key('pin_$label'),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          onTap: onTap,
          child: Center(
            child: icon != null
                ? Icon(icon, color: c.textPrimary)
                : Text(label!, style: Theme.of(context).textTheme.headlineMedium),
          ),
        ),
      ),
    );
  }
}
