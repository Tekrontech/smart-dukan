import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

/// App-wide display preferences.
///
/// Milestone 1 keeps these in memory. Milestone 2 persists them to the
/// encrypted `app_settings` table (see DECISIONS.md D-004).
class AppPreferencesNotifier extends Notifier<AppPreferences> {
  @override
  AppPreferences build() => const AppPreferences();

  void setLanguage(AppLanguage language) => state = state.copyWith(language: language);
  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);
  void setUrduDigits(bool value) => state = state.copyWith(urduDigits: value);
}

final appPreferencesProvider =
    NotifierProvider<AppPreferencesNotifier, AppPreferences>(AppPreferencesNotifier.new);
