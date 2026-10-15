import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/biometric_service.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/pin_pad.dart';

/// App lock (spec Section 9): PIN, optional fingerprint, staff picker when
/// more than one user exists. Five wrong tries → 30-second wait.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pad = GlobalKey<PinPadState>();
  List<AppUser> _users = const [];
  AppUser? _selected;
  String? _error;
  bool _busy = false;
  bool _bio = false;
  int _fails = 0;
  DateTime? _blockedUntil;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final users = await ref.read(userServiceProvider).activeUsers();
    final settings = SettingsRepository(db);
    final lastId = await settings.get(SettingKeys.lastUserId);
    final bioOn = await settings.getBool(SettingKeys.biometric);
    final bioOk = bioOn && await ref.read(biometricServiceProvider).available();
    if (!mounted) return;
    setState(() {
      _users = users;
      _selected = users.length == 1 ? users.first : users.where((u) => u.id == lastId).firstOrNull;
      _bio = bioOk;
    });
    if (bioOk && _selected != null) _biometric();
  }

  Future<void> _biometric() async {
    final user = _selected ?? _users.where((u) => u.role == UserRole.owner).firstOrNull;
    if (user == null) return;
    final ok = await ref.read(biometricServiceProvider).authenticate(context.l10n.biometricReason);
    if (ok && mounted) await ref.read(sessionProvider.notifier).unlock(user);
  }

  Future<void> _check(String pin) async {
    final user = _selected;
    if (user == null) return;
    final blocked = _blockedUntil;
    if (blocked != null && DateTime.now().isBefore(blocked)) {
      _pad.currentState?.clear();
      return;
    }
    setState(() => _busy = true);
    final ok = await ref.read(userServiceProvider).verify(user, pin);
    if (!mounted) return;
    if (ok) {
      await ref.read(sessionProvider.notifier).unlock(user);
      return;
    }
    _pad.currentState?.clear();
    _fails++;
    setState(() {
      _busy = false;
      _error = context.l10n.wrongPin;
      if (_fails >= 5) {
        _fails = 0;
        _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) return;
          final left = _blockedUntil!.difference(DateTime.now()).inSeconds;
          setState(() => _error = left > 0 ? context.l10n.tooManyAttempts(left) : null);
          if (left <= 0) t.cancel();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final business = ref.watch(sessionProvider).business;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(22)),
                    child: Icon(Icons.storefront_rounded, size: 40, color: theme.colorScheme.onPrimary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(business?.name ?? l.appTitle, style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.lg),
                  if (_users.length > 1) ...[
                    Text(l.whoIsUsing, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final u in _users)
                          ChoiceChip(
                            avatar: CircleAvatar(child: Text(u.name.characters.first.toUpperCase())),
                            label: Text(u.name),
                            selected: _selected?.id == u.id,
                            onSelected: (_) => setState(() {
                              _selected = u;
                              _error = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  if (_selected != null) ...[
                    Text(l.enterPin, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    PinPad(
                      key: _pad,
                      onCompleted: _check,
                      error: _error,
                      busy: _busy,
                      extraKey: _bio
                          ? IconButton(
                              key: const Key('lock_bio'),
                              tooltip: l.useFingerprint,
                              iconSize: 32,
                              onPressed: _biometric,
                              icon: Icon(Icons.fingerprint_rounded, color: c.primary),
                            )
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
