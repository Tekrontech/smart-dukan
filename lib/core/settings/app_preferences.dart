import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'settings_repository.dart';

/// The three display languages from spec Section 4.
enum AppLanguage {
  english(Locale('en')),
  romanUrdu(Locale('en', 'PK')),
  urdu(Locale('ur'));

  const AppLanguage(this.locale);
  final Locale locale;

  bool get isRtl => this == AppLanguage.urdu;
}

@immutable
class AppPreferences {
  const AppPreferences({
    this.language = AppLanguage.romanUrdu,
    this.themeMode = ThemeMode.system,
    this.urduDigits = false,
  });

  final AppLanguage language;
  final ThemeMode themeMode;
  final bool urduDigits;

  AppPreferences copyWith({AppLanguage? language, ThemeMode? themeMode, bool? urduDigits}) => AppPreferences(
        language: language ?? this.language,
        themeMode: themeMode ?? this.themeMode,
        urduDigits: urduDigits ?? this.urduDigits,
      );

  static AppPreferences fromSettings(Map<String, String> s) => AppPreferences(
        language: AppLanguage.values.asNameMap()[s[SettingKeys.language]] ?? AppLanguage.romanUrdu,
        themeMode: ThemeMode.values.asNameMap()[s[SettingKeys.theme]] ?? ThemeMode.system,
        urduDigits: s[SettingKeys.urduDigits] == 'true',
      );
}

/// Preferences loaded at start-up (bootstrap overrides this).
final initialPreferencesProvider = Provider<AppPreferences>((ref) => const AppPreferences());

/// App-wide display preferences, saved to the encrypted `app_settings`
/// table (no shared_preferences — everything stays encrypted).
class AppPreferencesNotifier extends Notifier<AppPreferences> {
  @override
  AppPreferences build() => ref.read(initialPreferencesProvider);

  void setLanguage(AppLanguage language) {
    state = state.copyWith(language: language);
    _save(SettingKeys.language, language.name);
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _save(SettingKeys.theme, mode.name);
  }

  void setUrduDigits(bool value) {
    state = state.copyWith(urduDigits: value);
    _save(SettingKeys.urduDigits, '$value');
  }

  void _save(String key, String value) {
    try {
      ref.read(settingsRepoProvider).set(key, value);
    } on UnimplementedError {
      // No database yet (widget tests without one): keep in memory.
    }
  }
}

final appPreferencesProvider =
    NotifierProvider<AppPreferencesNotifier, AppPreferences>(AppPreferencesNotifier.new);
