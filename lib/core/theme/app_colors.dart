import 'package:flutter/material.dart';

/// Design tokens — Glow / soft luxury aesthetic.
class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFFF8E8EE);
  static const primaryAccent = Color(0xFFD98FA3);
  static const background = Color(0xFFFFF9FB);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF2E2E2E);
  static const textSecondary = Color(0xFF8E8E93);

  // Extended (semantic) — Cormorant-rose accents.
  /// Deep rose used for italic accents in headlines and CTAs.
  /// Mapped from oklch(0.45 0.10 12).
  static const roseDeep = Color(0xFF6E2A37);
  static const roseShadow = Color(0xFF4D1F2A);
  static const blush = Color(0xFFFCEEF2);
  static const blush2 = Color(0xFFF5DCE4);
  static const champagne = Color(0xFFF5EBDC);
  /// Gold, mapped from oklch(0.78 0.07 75).
  static const gold = Color(0xFFD4A87A);
  static const sage = Color(0xFF9BBFA5);

  // Status
  static const success = Color(0xFF6FA088);
  static const warning = Color(0xFFC97D7D);
  static const danger = Color(0xFFC97D7D);
  static const info = Color(0xFF5BA3D0);

  // Lines / shadows
  static const divider = Color(0x0F2E2E2E); // 6%
  static const dividerStrong = Color(0x1A2E2E2E); // 10%
  static const shadow = Color(0x14D98FA3);
  static const shadowCard = Color(0x2ED98FA3); // 18%
  static const shadowLift = Color(0x40D98FA3); // 25%
}

class AppShadows {
  AppShadows._();

  static const soft = [
    BoxShadow(
      color: Color(0x14D98FA3),
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  static const card = [
    BoxShadow(
      color: Color(0x2ED98FA3),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -8,
    ),
  ];

  static const lift = [
    BoxShadow(
      color: Color(0x40D98FA3),
      blurRadius: 40,
      offset: Offset(0, 18),
      spreadRadius: -16,
    ),
  ];
}
