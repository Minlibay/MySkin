import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Glow / soft luxury typography:
/// - Cormorant Garamond — serif for headlines and italic accents
/// - Inter — clean sans for UI body
/// - JetBrains Mono — uppercase eyebrow labels with letter-spacing
///
/// Fonts are **bundled** in the app (see pubspec.yaml `fonts:` section), not
/// fetched from Google Fonts at runtime. This is what guarantees the type
/// looks identical on iOS and Android from the first frame — no flash, no
/// network dependency, no platform-specific fallback shifting kerning.
class AppTypography {
  AppTypography._();

  static const String _serif = 'CormorantGaramond';
  static const String _sans = 'Inter';
  static const String _mono = 'JetBrainsMono';

  // ===== Serif (Cormorant Garamond) =====

  /// 36px serif — used for hero titles in onboarding/scan/result.
  static const TextStyle display = TextStyle(
    fontFamily: _serif,
    fontSize: 36,
    fontWeight: FontWeight.w500,
    height: 1.05,
    letterSpacing: -0.72,
    color: AppColors.textPrimary,
  );

  /// 32px serif — large premium accent.
  static const TextStyle serifLg = TextStyle(
    fontFamily: _serif,
    fontSize: 32,
    fontWeight: FontWeight.w500,
    height: 1.1,
    letterSpacing: -0.64,
    color: AppColors.textPrimary,
  );

  /// 28px serif H1.
  static const TextStyle h1 = TextStyle(
    fontFamily: _serif,
    fontSize: 28,
    fontWeight: FontWeight.w500,
    height: 1.15,
    letterSpacing: -0.56,
    color: AppColors.textPrimary,
  );

  /// 22px serif H2.
  static const TextStyle h2 = TextStyle(
    fontFamily: _serif,
    fontSize: 22,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: -0.22,
    color: AppColors.textPrimary,
  );

  /// 18px serif H3.
  static const TextStyle h3 = TextStyle(
    fontFamily: _serif,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.25,
    color: AppColors.textPrimary,
  );

  /// Italic accent in roseDeep. Use inside Text.rich or with the [serifItalic] helper.
  static TextStyle serifItalic({double fontSize = 28, Color? color}) =>
      TextStyle(
        fontFamily: _serif,
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.italic,
        height: 1.15,
        letterSpacing: fontSize * -0.01,
        color: color ?? AppColors.roseDeep,
      );

  // ===== Sans (Inter) =====

  static const TextStyle body = TextStyle(
    fontFamily: _sans,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _sans,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: _sans,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontFamily: _sans,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _sans,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle micro = TextStyle(
    fontFamily: _sans,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontFamily: _sans,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: Colors.white,
  );

  // ===== Mono (JetBrains Mono) =====

  /// 10px UPPERCASE letter-spaced — section eyebrows.
  /// Use with `text.toUpperCase()` since style alone doesn't capitalise.
  static TextStyle eyebrow({Color? color}) => TextStyle(
        fontFamily: _mono,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.6,
        color: color ?? AppColors.textSecondary,
      );
}
