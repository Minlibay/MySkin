import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Live ambient-light classification for the scan camera. Drives the status
/// pill at the top of the scan screen and is used by capture validation.
enum LightLevel { tooDark, ok, tooBright, unknown }

extension LightLevelDisplay on LightLevel {
  String get label {
    switch (this) {
      case LightLevel.tooDark:
        return 'Темновато';
      case LightLevel.ok:
        return 'Дневной свет · ОК';
      case LightLevel.tooBright:
        return 'Слишком ярко';
      case LightLevel.unknown:
        return 'Свет: проверяю…';
    }
  }

  Color get color {
    switch (this) {
      case LightLevel.ok:
        return AppColors.success;
      case LightLevel.tooDark:
      case LightLevel.tooBright:
        return AppColors.warning;
      case LightLevel.unknown:
        return Colors.white.withOpacity(0.6);
    }
  }
}

/// Translucent circular icon button used in the scan top bar (flip camera,
/// open from gallery, close). Sized 40 and respects safe area when wrapped.
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.white.withOpacity(0.18),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// Pill at the top of the scan screen surfacing the current light reading.
class LightStatusPill extends StatelessWidget {
  const LightStatusPill({super.key, required this.level});
  final LightLevel level;

  @override
  Widget build(BuildContext context) {
    final color = level.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            level.label,
            style: AppTypography.caption.copyWith(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The big capture button. Shows a spinner while busy.
class ShutterButton extends StatelessWidget {
  const ShutterButton({super.key, required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: AppColors.primaryAccent.withOpacity(0.4),
              width: 4,
            ),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: AppColors.roseDeep,
                      strokeWidth: 2.6,
                    ),
                  )
                : Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: AppColors.roseDeep,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
