import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/biometric_service.dart';
import '../../../core/settings/app_preferences.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/primary_button.dart';
import '../../settings/application/user_service.dart';
import '../application/business_setup_service.dart';
import '../application/demo_data_service.dart';

/// First launch, under 60 seconds (spec 5.1): language → shop → demo data
/// → PIN (+ fingerprint) → Home with coach marks.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { language, shop, demo, pin, confirmPin, working }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.language;
  final _form = GlobalKey<FormState>();
  final _shop = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _pinPad = GlobalKey<PinPadState>();
  BusinessType _type = BusinessType.mobileShop;
  bool _demo = false;
  String? _firstPin;
  String? _pinError;
  bool _fingerprint = false;
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    ref.read(biometricServiceProvider).available().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
  }

  @override
  void dispose() {
    for (final c in [_shop, _owner, _phone, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(_Step s) => setState(() => _step = s);

  Future<void> _finish(String pin) async {
    _go(_Step.working);
    final db = ref.read(databaseProvider);
    final ok = await guard(context, () async {
      final business = await BusinessSetupService(db).createBusiness(
        name: _shop.text.trim(),
        ownerName: _owner.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        type: _type,
      );
      final users = UserService(db, businessId: business.id);
      final ownerId = await users.createUser(
        name: _owner.text.trim().isEmpty ? _shop.text.trim() : _owner.text.trim(),
        role: UserRole.owner,
        pin: pin,
      );
      final settings = SettingsRepository(db);
      final prefs = ref.read(appPreferencesProvider);
      await settings.set(SettingKeys.language, prefs.language.name, businessId: business.id);
      await settings.set(SettingKeys.biometric, '$_fingerprint', businessId: business.id);
      await settings.set(SettingKeys.coachShown, 'false', businessId: business.id);
      if (_demo) {
        await DemoDataService(db, businessId: business.id, userId: ownerId).load();
      }
      final owner = (await users.activeUsers()).firstWhere((u) => u.id == ownerId);
      final session = ref.read(sessionProvider.notifier);
      await session.reloadBusiness();
      await session.unlock(owner);
      return true;
    });
    if (ok == null && mounted) _go(_Step.pin);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.language,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        switch (_step) {
          case _Step.shop:
            _go(_Step.language);
          case _Step.demo:
            _go(_Step.shop);
          case _Step.pin:
            _go(_Step.demo);
          case _Step.confirmPin:
            _go(_Step.pin);
          default:
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: AppSpacing.motion,
            // PIN and confirm-PIN share one page so the PinPad (GlobalKey) is never
            // in the tree twice during the transition.
            child: KeyedSubtree(key: ValueKey(_step == _Step.confirmPin ? _Step.pin : _step), child: _body(context)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    switch (_step) {
      case _Step.language:
        final prefs = ref.watch(appPreferencesProvider);
        return _Page(
          bottom: PrimaryButton(
              key: const Key('onb_next'), label: l.next, icon: Icons.arrow_forward_rounded, onPressed: () => _go(_Step.shop)),
          children: [
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(28)),
                child: Icon(Icons.storefront_rounded, size: 56, color: theme.colorScheme.onPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l.appTitle, textAlign: TextAlign.center, style: theme.textTheme.displaySmall),
            Text(l.tagline, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: c.textSecondary)),
            const SizedBox(height: AppSpacing.xl),
            Text(l.chooseLanguage, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            for (final lang in AppLanguage.values)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ChoiceTile(
                  key: Key('lang_${lang.name}'),
                  label: switch (lang) {
                    AppLanguage.english => 'English',
                    AppLanguage.romanUrdu => 'Roman Urdu',
                    AppLanguage.urdu => 'اردو',
                  },
                  selected: prefs.language == lang,
                  onTap: () => ref.read(appPreferencesProvider.notifier).setLanguage(lang),
                ),
              ),
          ],
        );
      case _Step.shop:
        return Form(
          key: _form,
          child: _Page(
            title: l.shopSetupTitle,
            bottom: PrimaryButton(
              key: const Key('onb_next'),
              label: l.next,
              icon: Icons.arrow_forward_rounded,
              onPressed: () {
                if (_form.currentState!.validate()) _go(_Step.demo);
              },
            ),
            children: [
              TextFormField(
                key: const Key('shop_name'),
                controller: _shop,
                decoration: InputDecoration(labelText: l.shopName),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('owner_name'),
                controller: _owner,
                decoration: InputDecoration(labelText: l.ownerName),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phone,
                decoration: InputDecoration(labelText: '${l.phone} (${l.optional})'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(controller: _city, decoration: InputDecoration(labelText: l.city)),
              const SizedBox(height: AppSpacing.lg),
              Text(l.businessType, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final t in BusinessType.values)
                    ChoiceChip(
                      label: Text(businessTypeLabel(context, t)),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t),
                    ),
                ],
              ),
            ],
          ),
        );
      case _Step.demo:
        return _Page(
          title: l.demoTitle,
          bottom: PrimaryButton(
              key: const Key('onb_next'), label: l.next, icon: Icons.arrow_forward_rounded, onPressed: () => _go(_Step.pin)),
          children: [
            Text(l.demoBody, style: theme.textTheme.bodyLarge?.copyWith(color: c.textSecondary)),
            const SizedBox(height: AppSpacing.lg),
            _ChoiceTile(
                key: const Key('demo_yes'),
                label: l.demoYes,
                icon: Icons.auto_awesome_rounded,
                selected: _demo,
                onTap: () => setState(() => _demo = true)),
            const SizedBox(height: AppSpacing.sm),
            _ChoiceTile(
                key: const Key('demo_no'),
                label: l.demoNo,
                icon: Icons.check_box_outline_blank_rounded,
                selected: !_demo,
                onTap: () => setState(() => _demo = false)),
          ],
        );
      case _Step.pin:
      case _Step.confirmPin:
        final confirm = _step == _Step.confirmPin;
        return _Page(
          title: confirm ? l.confirmPinTitle : l.setPinTitle,
          children: [
            Text(l.setPinBody, style: theme.textTheme.bodyLarge?.copyWith(color: c.textSecondary)),
            const SizedBox(height: AppSpacing.lg),
            PinPad(
              key: _pinPad,
              error: _pinError,
              onCompleted: (pin) {
                if (!confirm) {
                  _firstPin = pin;
                  _pinError = null;
                  _pinPad.currentState?.clear();
                  _go(_Step.confirmPin);
                } else if (pin == _firstPin) {
                  _finish(pin);
                } else {
                  _pinPad.currentState?.clear();
                  setState(() {
                    _pinError = l.pinMismatch;
                    _step = _Step.pin;
                  });
                }
              },
            ),
            if (_bioAvailable) ...[
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                value: _fingerprint,
                onChanged: (v) => setState(() => _fingerprint = v),
                title: Text(l.enableFingerprint),
                secondary: const Icon(Icons.fingerprint_rounded),
              ),
            ],
          ],
        );
      case _Step.working:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text(l.settingUp, style: theme.textTheme.titleMedium),
            ],
          ),
        );
    }
  }
}

String businessTypeLabel(BuildContext context, BusinessType t) {
  final l = context.l10n;
  return switch (t) {
    BusinessType.mobileShop => l.btMobileShop,
    BusinessType.kiryana => l.btKiryana,
    BusinessType.garments => l.btGarments,
    BusinessType.pharmacy => l.btPharmacy,
    BusinessType.wholesale => l.btWholesale,
    BusinessType.other => l.btOther,
  };
}

class _Page extends StatelessWidget {
  const _Page({this.title, required this.children, this.bottom});

  final String? title;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (title != null) ...[
                Text(title!, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.md),
              ],
              ...children,
            ],
          ),
        ),
        if (bottom != null) Padding(padding: const EdgeInsets.all(AppSpacing.md), child: bottom),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: selected ? c.primaryContainer : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        side: BorderSide(color: selected ? c.primary : c.outline, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 18),
          child: Row(
            children: [
              if (icon != null) ...[Icon(icon, color: c.primary), const SizedBox(width: AppSpacing.md)],
              Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
              if (selected) Icon(Icons.check_circle_rounded, color: c.primary),
            ],
          ),
        ),
      ),
    );
  }
}
