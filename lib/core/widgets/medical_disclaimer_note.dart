import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../../features/legal/presentation/legal_viewer_screen.dart';

/// Tiny footer used under scan/routine results. Reminds the user that the
/// recommendation is informational and links to the full medical disclaimer
/// — required for compliance with RF healthcare law (63-ФЗ).
class MedicalDisclaimerNote extends StatelessWidget {
  const MedicalDisclaimerNote({super.key, this.padding});
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (ctx) => LegalViewerScreen(
              docKey: 'legal_medical',
              title: 'Медицинская оговорка',
              onBack: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
        behavior: HitTestBehavior.opaque,
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: AppTypography.caption.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
            children: [
              const TextSpan(
                text:
                    'Это не медицинское заключение. Рекомендации носят справочный характер. ',
              ),
              TextSpan(
                text: 'Подробнее',
                style: TextStyle(
                  color: AppColors.roseDeep,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.roseDeep.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
