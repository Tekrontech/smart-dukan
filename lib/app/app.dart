import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../core/settings/app_preferences.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

final routerProvider = Provider<GoRouter>((ref) => buildRouter());

class SmartDukanApp extends ConsumerWidget {
  const SmartDukanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPreferencesProvider);
    final urdu = prefs.language == AppLanguage.urdu;

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
