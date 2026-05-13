import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// AI agent avatar — gradient pill with optional italic «Л» monogram + a green
/// online dot. Use [monogram] = true wherever the avatar reads as a person
/// (home nudge, Лина header); leave it false for chrome uses like list bullets.
class LinaAvatar extends StatelessWidget {
  const LinaAvatar({
    super.key,
    this.size = 40,
    this.online = true,
    this.monogram = false,
  });

  final double size;
  final bool online;
  final bool monogram;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryAccent, AppColors.roseDeep],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.roseDeep.withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: monogram
                ? Padding(
                    // Optical bottom-right nudge — Cormorant italic «Л» reads
                    // off-centre without it because of the leftward stem and
                    // the upward right serif.
                    padding: EdgeInsets.only(left: size * 0.06),
                    child: Text(
                      'Л',
                      style: AppTypography.serifItalic(
                        fontSize: size * 0.55,
                        color: Colors.white,
                      ).copyWith(height: 1, letterSpacing: 0),
                    ),
                  )
                : null,
          ),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
