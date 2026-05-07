import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Tiny uppercase mono label — section eyebrow used throughout the design.
class EyebrowText extends StatelessWidget {
  const EyebrowText(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style:
          AppTypography.eyebrow(color: color ?? AppColors.textSecondary),
    );
  }
}
