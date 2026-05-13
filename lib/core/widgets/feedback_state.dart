import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Centered visual for the three non-content states a screen can be in:
/// loading, error/offline, or empty. Use the static factories so the spacing,
/// icon size, and palette stay consistent across the app.
class FeedbackState extends StatelessWidget {
  const FeedbackState._({
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.showSpinner = false,
  });

  final IconData icon;
  final String title;
  final String? body;
  final ({String label, VoidCallback onTap})? action;
  final bool showSpinner;

  /// Centered spinner with optional caption. Use while data is in flight.
  factory FeedbackState.loading({String? hint}) => FeedbackState._(
        icon: Icons.hourglass_top_rounded,
        title: hint ?? 'Загружаем…',
        showSpinner: true,
      );

  /// Network / server failure. Pass [onRetry] to expose a Повторить button.
  factory FeedbackState.error({
    String title = 'Не удалось загрузить',
    String body = 'Проверь интернет и попробуй ещё раз.',
    VoidCallback? onRetry,
  }) =>
      FeedbackState._(
        icon: Icons.cloud_off_rounded,
        title: title,
        body: body,
        action: onRetry == null
            ? null
            : (label: 'Повторить', onTap: onRetry),
      );

  /// Successful load but no data. Pass any CTA via [action].
  factory FeedbackState.empty({
    required IconData icon,
    required String title,
    String? body,
    ({String label, VoidCallback onTap})? action,
  }) =>
      FeedbackState._(
        icon: icon,
        title: title,
        body: body,
        action: action,
      );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: AppColors.primaryAccent,
                  strokeWidth: 2.5,
                ),
              )
            else
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.blush,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child:
                    Icon(icon, size: 30, color: AppColors.primaryAccent),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: AppTypography.h2, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(body!,
                  style: AppTypography.bodySecondary,
                  textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: action!.onTap,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.roseDeep,
                  textStyle: AppTypography.bodyMedium,
                ),
                child: Text(action!.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
