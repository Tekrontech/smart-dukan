import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../l10n/l10n.dart';
import '../theme/app_spacing.dart';
import '../widgets/pin_pad.dart';

/// Asks for the owner PIN before sensitive actions (spec Section 9:
/// reversals, price below minimum, stock adjustment, restore, export).
abstract class PinGate {
  Future<bool> requireOwner(BuildContext context, {String? reason});
}

/// Test / early-milestone stub (spec Section 11).
class AlwaysAllowPinGate implements PinGate {
  const AlwaysAllowPinGate();

  @override
  Future<bool> requireOwner(BuildContext context, {String? reason}) async => true;
}

class OwnerPinGate implements PinGate {
  OwnerPinGate(this.ref);

  final Ref ref;

  @override
  Future<bool> requireOwner(BuildContext context, {String? reason}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OwnerPinSheet(ref: ref, reason: reason),
    );
    return ok ?? false;
  }
}

final pinGateProvider = Provider<PinGate>((ref) => OwnerPinGate(ref));

class _OwnerPinSheet extends StatefulWidget {
  const _OwnerPinSheet({required this.ref, this.reason});

  final Ref ref;
  final String? reason;

  @override
  State<_OwnerPinSheet> createState() => _OwnerPinSheetState();
}

class _OwnerPinSheetState extends State<_OwnerPinSheet> {
  final _pad = GlobalKey<PinPadState>();
  String? _error;
  bool _busy = false;

  Future<void> _check(String pin) async {
    setState(() => _busy = true);
    final owner = await widget.ref.read(userServiceProvider).ownerForPin(pin);
    if (!mounted) return;
    if (owner != null) {
      Navigator.of(context).pop(true);
    } else {
      _pad.currentState?.clear();
      setState(() {
        _busy = false;
        _error = context.l10n.wrongPin;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(l.ownerPinTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(widget.reason ?? l.ownerPinBody, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            PinPad(key: _pad, onCompleted: _check, error: _error, busy: _busy),
          ],
        ),
      ),
    );
  }
}
