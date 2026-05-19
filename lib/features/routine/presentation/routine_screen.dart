import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/medical_disclaimer_note.dart';
import '../../../core/widgets/metric_ring.dart';
import '../../../core/widgets/routine_card.dart';
import '../../ai/domain/models.dart';
import '../../catalog/domain/product.dart';

class RoutineScreen extends StatelessWidget {
  const RoutineScreen({
    super.key,
    required this.result,
    this.onFollowUp,
    this.onBack,
    this.onOpenProduct,
  });

  final RoutineResult result;
  final VoidCallback? onFollowUp;
  final VoidCallback? onBack;
  final ValueChanged<Product>? onOpenProduct;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Твой уход'),
        leading: onBack != null
            ? IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new, size: 18))
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (result.skinSummary != null || result.skinScore != null) ...[
            _AnalysisHero(result: result),
            const SizedBox(height: AppSpacing.lg),
          ],
          _SectionHeader(emoji: '🌅', title: 'Утро'),
          const SizedBox(height: AppSpacing.sm),
          ..._staggered(result.morning),
          const SizedBox(height: AppSpacing.lg),
          _SectionHeader(emoji: '🌙', title: 'Вечер'),
          const SizedBox(height: AppSpacing.sm),
          ..._staggered(result.evening, baseDelay: 80),
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _BlockList(
              icon: '⚠️',
              title: 'Предупреждения',
              items: result.warnings,
              tint: AppColors.warning.withOpacity(0.15),
            ),
          ],
          if (result.tips.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _BlockList(
              icon: '💡',
              title: 'Советы',
              items: result.tips,
              tint: AppColors.primary,
            ),
          ],
          if (onFollowUp != null) ...[
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Сообщить об изменениях',
              icon: Icons.refresh,
              onPressed: onFollowUp,
              variant: AppButtonVariant.soft,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const MedicalDisclaimerNote(),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  List<Widget> _staggered(List<RoutineStep> steps, {int baseDelay = 0}) {
    return [
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 300 + baseDelay + i * 90),
            tween: Tween(begin: 0, end: 1),
            curve: Curves.easeOut,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 16),
                child: child,
              ),
            ),
            child: RoutineCard(
              stepNumber: i + 1,
              title: steps[i].title,
              ingredients: steps[i].ingredients,
              explanation: steps[i].explanation,
              product: steps[i].product,
              recommendation: steps[i].recommendation,
              onOpenProduct: onOpenProduct,
            ),
          ),
        ),
    ];
  }
}

class _AnalysisHero extends StatelessWidget {
  const _AnalysisHero({required this.result});
  final RoutineResult result;

  Color _scoreColor(int s) {
    if (s >= 70) return AppColors.success;
    if (s >= 50) return AppColors.primaryAccent;
    if (s >= 30) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final score = result.skinScore;
    return AppCard(
      color: AppColors.primary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (score != null) ...[
            MetricRing(
              value: score,
              size: 64,
              stroke: 5,
              color: _scoreColor(score),
              suffix: null,
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EyebrowText('Анализ', color: AppColors.roseDeep),
                const SizedBox(height: 4),
                if (result.skinSummary != null)
                  Text(result.skinSummary!,
                      style: AppTypography.body),
                if (result.confidence != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Уверенность ${(result.confidence! * 100).round()}%',
                    style: AppTypography.caption,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.emoji, required this.title});
  final String emoji;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: AppSpacing.xs),
        Text(title, style: AppTypography.h2),
      ],
    );
  }
}

class _BlockList extends StatelessWidget {
  const _BlockList({
    required this.icon,
    required this.title,
    required this.items,
    required this.tint,
  });
  final String icon;
  final String title;
  final List<String> items;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: AppSpacing.xs),
              Text(title,
                  style: AppTypography.body
                      .copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ...items.map((t) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $t', style: AppTypography.body),
              )),
        ],
      ),
    );
  }
}
