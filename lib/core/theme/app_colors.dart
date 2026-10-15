import 'package:flutter/material.dart';

/// Colour tokens from spec Section 4.
///
/// Widgets must never use raw hex values. Read colours via
/// `Theme.of(context).colorScheme` or `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryContainer,
    required this.secondary,
    required this.success,
    required this.danger,
    required this.warning,
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.outline,
  });

  final Color primary;
  final Color primaryContainer;

  /// Accent: Pro badge, attention.
  final Color secondary;

  /// Lena / money in / profit.
  final Color success;

  /// Dena / money out / loss / delete.
  final Color danger;

  /// Low stock, due soon.
  final Color warning;
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color outline;

  static const light = AppColors(
    primary: Color(0xFF0F6E56),
    primaryContainer: Color(0xFFD7F2E8),
    secondary: Color(0xFFF2A541),
    success: Color(0xFF1E8E3E),
    danger: Color(0xFFC62828),
    warning: Color(0xFFE37400),
    background: Color(0xFFF6F8F7),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF13201B),
    textSecondary: Color(0xFF5B6B65),
    outline: Color(0xFFDCE3E0),
  );

  static const dark = AppColors(
    primary: Color(0xFF4FC3A1),
    primaryContainer: Color(0xFF12352C),
    secondary: Color(0xFFF5B867),
    success: Color(0xFF5BD17A),
    danger: Color(0xFFEF6B6B),
    warning: Color(0xFFFFB74D),
    background: Color(0xFF0F1412),
    surface: Color(0xFF1A211E),
    textPrimary: Color(0xFFE8EFEC),
    textSecondary: Color(0xFF9DB0A8),
    outline: Color(0xFF2C3733),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith({
    Color? primary,
    Color? primaryContainer,
    Color? secondary,
    Color? success,
    Color? danger,
    Color? warning,
    Color? background,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? outline,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      secondary: secondary ?? this.secondary,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      outline: outline ?? this.outline,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
    );
  }
}
