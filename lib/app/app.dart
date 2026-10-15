import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../core/money/money_format.dart';
import '../core/settings/app_preferences.dart';
import '../core/settings/settings_repository.dart';
import '../core/theme/app_theme.dart';
import 'providers.dart';
import 'router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);
  return buildRouter(ref, refresh);
});

class SmartDukanApp extends ConsumerStatefulWidget {
  const SmartDukanApp({super.key});

  @override
  ConsumerState<SmartDukanApp> createState() => _SmartDukanAppState();
}

class _SmartDukanAppState extends ConsumerState<SmartDukanApp> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onHide() => _hiddenAt = DateTime.now();

  /// Lock after N minutes in background (spec Section 9, default 2).
  Future<void> _onShow() async {
    final hidden = _hiddenAt;
    _hiddenAt = null;
    final session = ref.read(sessionProvider);
    if (hidden == null || !session.onboarded || session.locked) return;
    final minutes = await ref.read(settingsRepoProvider).getInt(SettingKeys.autoLockMinutes, fallback: 2);
    if (DateTime.now().difference(hidden) >= Duration(minutes: minutes)) {
      ref.read(sessionProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appPreferencesProvider);
    final urdu = prefs.language == AppLanguage.urdu;
    MoneyFormat.useUrduDigits = prefs.urduDigits;

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(urdu: urdu),
      darkTheme: AppTheme.dark(urdu: urdu),
      themeMode: prefs.themeMode,
      locale: prefs.language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
