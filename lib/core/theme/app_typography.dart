import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Glow / soft luxury typography:
/// - Cormorant Garamond — serif for headlines and italic accents
/// - Inter — clean sans for UI body
/// - JetBrains Mono — uppercase eyebrow labels with letter-spacing
class AppTypography {
  AppTypography._();

  // ===== Serif (Cormorant Garamond) =====

  /// 36px serif — used for hero titles in onboarding/scan/result.
  static final TextStyle display = GoogleFonts.cormorantGaramond(
    fontSize: 36,
    fontWeight: FontWeight.w500,
    height: 1.05,
    letterSpacing: -0.72,
    color: AppColors.textPrimary,
  );

  /// 32px serif — large premium accent.
  static final TextStyle serifLg = GoogleFonts.cormorantGaramond(
    fontSize: 32,
    fontWeight: FontWeight.w500,
    height: 1.1,
    letterSpacing: -0.64,
    color: AppColors.textPrimary,
  );

  /// 28px serif H1.
  static final TextStyle h1 = GoogleFonts.cormorantGaramond(
    fontSize: 28,
    fontWeight: FontWeight.w500,
    height: 1.15,
    letterSpacing: -0.56,
    color: AppColors.textPrimary,
  );

  /// 22px serif H2.
  static final TextStyle h2 = GoogleFonts.cormorantGaramond(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: -0.22,
    color: AppColors.textPrimary,
  );

  /// 18px serif H3.
  static final TextStyle h3 = GoogleFonts.cormorantGaramond(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.25,
    color: AppColors.textPrimary,
  );

  /// Italic accent in roseDeep. Use inside Text.rich or with the [serifItalic] helper.
  static TextStyle serifItalic({double fontSize = 28, Color? color}) =>
      GoogleFonts.cormorantGaramond(
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.italic,
        height: 1.15,
        letterSpacing: fontSize * -0.01,
        color: color ?? AppColors.roseDeep,
      );

  // ===== Sans (Inter) =====

  static final TextStyle body = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textPrimary,
  );

  static final TextStyle bodyMedium = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static final TextStyle bodySm = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textPrimary,
  );

  static final TextStyle bodySecondary = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  static final TextStyle caption = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static final TextStyle micro = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textSecondary,
  );

  static final TextStyle button = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: Colors.white,
  );

  // ===== Mono (JetBrains Mono) =====

  /// 10px UPPERCASE letter-spaced — section eyebrows.
  /// Use with `text.toUpperCase()` since style alone doesn't capitalise.
  static TextStyle eyebrow({Color? color}) => GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.6,
        color: color ?? AppColors.textSecondary,
      );
}
