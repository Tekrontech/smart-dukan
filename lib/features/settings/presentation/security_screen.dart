import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/biometric_service.dart';
import '../../../core/security/pin_gate.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/pin_pad.dart';

/// PIN, fingerprint, auto-lock and shop rules (spec Section 9).
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  Map<String, String> _s = const {};
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ref.read(settingsRepoProvider).all();
    final bio = await ref.read(biometricServiceProvider).available();
    if (mounted) {
      setState(() {
        _s = s;
        _bioAvailable = bio;
      });
    }
  }

  Future<void> _set(String key, String value) async {
    await ref.read(settingsRepoProvider).set(key, value, businessId: ref.read(sessionProvider).business?.id ?? '');
    await _load();
  }

  Future<void> _changePin() async {
    final pin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewPinSheet(),
    );
    if (pin == null || !mounted) return;
    final user = ref.read(sessionProvider).user!;
    final ok = await guard(context, () async {
      await ref.read(userServiceProvider).changePin(user.id, pin);
      return true;
    });
    if (ok == true && mounted) showMessage(context, context.l10n.saved);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final owner = ref.watch(sessionProvider).can.settings;
    final lock = int.tryParse(_s[SettingKeys.autoLockMinutes] ?? '') ?? 2;
    final retention = int.tryParse(_s[SettingKeys.cnicRetentionMonths] ?? '') ?? 12;
    return Scaffold(
      appBar: AppBar(title: Text(l.securitySection)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          ListTile(leading: const Icon(Icons.password_rounded), title: Text(l.changePin), onTap: _changePin),
          if (_bioAvailable)
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded),
              title: Text(l.enableFingerprint),
              value: _s[SettingKeys.biometric] == 'true',
              onChanged: (v) => _set(SettingKeys.biometric, '$v'),
            ),
          if (owner) ...[
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l.autoLock),
              trailing: DropdownButton<int>(
                value: lock,
                items: [for (final m in [1, 2, 5, 10, 30]) DropdownMenuItem(value: m, child: Text(l.minutes(m)))],
                onChanged: (v) => _set(SettingKeys.autoLockMinutes, '$v'),
              ),
            ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.remove_shopping_cart_outlined),
              title: Text(l.allowNegativeStock),
              value: _s[SettingKeys.allowNegativeStock] == 'true',
              onChanged: (v) async {
                if (await ref.read(pinGateProvider).requireOwner(context)) {
                  await _set(SettingKeys.allowNegativeStock, '$v');
                }
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.request_quote_outlined),
              title: Text(l.salesTaxSetting),
              value: _s[SettingKeys.taxEnabled] == 'true',
              onChanged: (v) => _set(SettingKeys.taxEnabled, '$v'),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.badge_outlined),
              title: Text(l.cnicFields),
              value: _s[SettingKeys.cnicEnabled] == 'true',
              onChanged: (v) => _set(SettingKeys.cnicEnabled, '$v'),
            ),
            if (_s[SettingKeys.cnicEnabled] == 'true')
              ListTile(
                leading: const Icon(Icons.auto_delete_outlined),
                title: Text(l.cnicRetention),
                trailing: DropdownButton<int>(
                  value: retention,
                  items: [for (final m in [3, 6, 12, 24]) DropdownMenuItem(value: m, child: Text(l.months(m)))],
                  onChanged: (v) => _set(SettingKeys.cnicRetentionMonths, '$v'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Asks for a new 4-digit PIN twice; returns it.
class _NewPinSheet extends StatefulWidget {
  const _NewPinSheet();

  @override
  State<_NewPinSheet> createState() => _NewPinSheetState();
}

class _NewPinSheetState extends State<_NewPinSheet> {
  final _pad = GlobalKey<PinPadState>();
  String? _first;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_first == null ? l.setPinTitle : l.confirmPinTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            PinPad(
              key: _pad,
              error: _error,
              onCompleted: (pin) {
                if (_first == null) {
                  _pad.currentState?.clear();
                  setState(() {
                    _first = pin;
                    _error = null;
                  });
                } else if (pin == _first) {
                  Navigator.of(context).pop(pin);
                } else {
                  _pad.currentState?.clear();
                  setState(() {
                    _first = null;
                    _error = l.pinMismatch;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Re-usable: new-PIN sheet for staff creation.
Future<String?> askNewPin(BuildContext context) =>
    showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const _NewPinSheet());
