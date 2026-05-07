import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant { primary, accent, ghost, soft }

/// Pill button — 56px height, premium feel from the Glow / soft luxury system.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.accent,
    this.loading = false,
    this.icon,
    this.trailingIcon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool loading;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool expanded;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    lowerBound: 0.0,
    upperBound: 0.04,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isDisabled => widget.onPressed == null || widget.loading;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (widget.variant) {
      AppButtonVariant.primary => (AppColors.textPrimary, Colors.white, null),
      AppButtonVariant.accent => (AppColors.roseDeep, Colors.white, null),
      AppButtonVariant.soft => (AppColors.primary, AppColors.roseDeep, null),
      AppButtonVariant.ghost => (
          Colors.transparent,
          AppColors.textPrimary,
          AppColors.dividerStrong,
        ),
    };

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      onTap: _isDisabled ? null : widget.onPressed,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) =>
            Transform.scale(scale: 1 - _ctrl.value, child: child),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _isDisabled ? 0.5 : 1.0,
          child: Container(
            width: widget.expanded ? double.infinity : null,
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: border != null ? Border.all(color: border) : null,
              boxShadow: widget.variant == AppButtonVariant.accent ||
                      widget.variant == AppButtonVariant.primary
                  ? [
                      BoxShadow(
                        color: AppColors.shadowCard,
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                        spreadRadius: -8,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize:
                  widget.expanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.loading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(fg),
                    ),
                  )
                else if (widget.icon != null) ...[
                  Icon(widget.icon, color: fg, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                ],
                if (!widget.loading)
                  Text(
                    widget.label,
                    style: AppTypography.button.copyWith(color: fg),
                  ),
                if (!widget.loading && widget.trailingIcon != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(widget.trailingIcon, color: fg, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
