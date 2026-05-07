import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum GlowVariant { blush, sunrise, deep, champagne }

/// Two blurred coloured orbs rendered behind a screen.
/// Pixels match the Figma "Glow / soft luxury" aesthetic.
class GlowBackground extends StatelessWidget {
  const GlowBackground({super.key, this.variant = GlowVariant.blush});

  final GlowVariant variant;

  @override
  Widget build(BuildContext context) {
    final orbs = _orbsFor(variant);
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          for (final o in orbs)
            Positioned(
              left: o.x,
              top: o.y,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(
                  width: o.size,
                  height: o.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: o.color.withOpacity(o.opacity),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<_Orb> _orbsFor(GlowVariant v) => switch (v) {
        GlowVariant.blush => const [
            _Orb(AppColors.primaryAccent, 320, -80, -100, 0.35),
            _Orb(AppColors.blush2, 280, 240, 480, 0.45),
          ],
        GlowVariant.sunrise => const [
            _Orb(AppColors.blush2, 360, -120, -120, 0.55),
            _Orb(AppColors.gold, 220, 260, 620, 0.25),
          ],
        GlowVariant.deep => const [
            _Orb(AppColors.roseDeep, 380, -120, -80, 0.18),
            _Orb(AppColors.primaryAccent, 280, 220, 600, 0.30),
          ],
        GlowVariant.champagne => const [
            _Orb(AppColors.champagne, 360, -120, -80, 0.6),
            _Orb(AppColors.blush, 280, 220, 500, 0.5),
          ],
      };
}

class _Orb {
  const _Orb(this.color, this.size, this.x, this.y, this.opacity);
  final Color color;
  final double size;
  final double x;
  final double y;
  final double opacity;
}
