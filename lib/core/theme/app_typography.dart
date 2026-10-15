import 'package:flutter/material.dart';

/// Typography from spec Section 4.
///
/// Scale: Display 32/40 bold, Title 20/28 semibold, Body 16/24,
/// Label 14/20 medium, Caption 12/16. Numbers use tabular figures.
///
/// English / Roman Urdu use Inter. Urdu uses Noto Nastaliq Urdu for headings
/// and Noto Naskh Arabic for body (Nastaliq is too tall for dense lists).
/// If the font assets are not bundled yet, Flutter falls back to the system
/// font automatically.
class AppTypography {
  AppTypography._();

  static const String latinFamily = 'Inter';
  static const String urduHeadingFamily = 'NotoNastaliqUrdu';
  static const String urduBodyFamily = 'NotoNaskhArabic';

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextTheme textTheme({required Color primary, required Color secondary, required bool urdu}) {
    final heading = urdu ? urduHeadingFamily : latinFamily;
    final body = urdu ? urduBodyFamily : latinFamily;
    // Latin fallback keeps numbers, IMEIs and SKUs rendering in Inter
    // inside Urdu text.
    const fallback = [latinFamily];

    // Nastaliq needs extra line height so ascenders/descenders aren't clipped.
    double h(double latinHeight) => urdu ? latinHeight * 1.35 : latinHeight;

    TextStyle s(String family, double size, double lineHeight, FontWeight w, Color c) => TextStyle(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontSize: size,
          height: h(lineHeight / size),
          fontWeight: w,
          color: c,
          fontFeatures: tabular,
        );

    return TextTheme(
      displayLarge: s(heading, 32, 40, FontWeight.w700, primary),
      displayMedium: s(heading, 32, 40, FontWeight.w700, primary),
      displaySmall: s(heading, 28, 36, FontWeight.w700, primary),
      headlineMedium: s(heading, 24, 32, FontWeight.w600, primary),
      titleLarge: s(heading, 20, 28, FontWeight.w600, primary),
      titleMedium: s(body, 16, 24, FontWeight.w600, primary),
      titleSmall: s(body, 14, 20, FontWeight.w600, primary),
      bodyLarge: s(body, 16, 24, FontWeight.w400, primary),
      bodyMedium: s(body, 14, 20, FontWeight.w400, primary),
      bodySmall: s(body, 12, 16, FontWeight.w400, secondary),
      labelLarge: s(body, 14, 20, FontWeight.w500, primary),
      labelMedium: s(body, 12, 16, FontWeight.w500, secondary),
      labelSmall: s(body, 11, 16, FontWeight.w500, secondary),
    );
  }
}
