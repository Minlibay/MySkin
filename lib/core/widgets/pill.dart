import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum PillVariant { soft, outline, dark, success, warning }

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.variant = PillVariant.soft,
    this.icon,
    this.dot = false,
  });

  final String label;
  final PillVariant variant;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (variant) {
      PillVariant.soft => (AppColors.primary, AppColors.roseDeep),
      PillVariant.outline => (
          AppColors.surface.withOpacity(0.5),
          AppColors.textSecondary,
        ),
      PillVariant.dark => (AppColors.textPrimary, Colors.white),
      PillVariant.success => (
          AppColors.success.withOpacity(0.14),
          AppColors.success,
        ),
      PillVariant.warning => (
          AppColors.warning.withOpacity(0.14),
          AppColors.warning,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: variant == PillVariant.outline
            ? Border.all(color: AppColors.dividerStrong)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
