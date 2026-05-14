import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/glow_background.dart';

/// Three-slide first-run walkthrough explaining the order things happen in.
/// Pure presentational widget — parent decides when to show/hide and where
/// to persist the "seen" flag.
class WelcomeTutorialScreen extends StatefulWidget {
  const WelcomeTutorialScreen({super.key, required this.onFinish});

  /// Fired both on the final "Начать" tap and on the early "Пропустить" link.
  /// Parent should persist tutorial_seen=true server-side and route to home.
  final VoidCallback onFinish;

  @override
  State<WelcomeTutorialScreen> createState() => _WelcomeTutorialScreenState();
}

class _WelcomeTutorialScreenState extends State<WelcomeTutorialScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = <_Slide>[
    _Slide(
      icon: Icons.center_focus_strong_rounded,
      iconAccent: AppColors.primaryAccent,
      eyebrow: 'Шаг 1',
      title: 'Сначала — скан кожи',
      body:
          'Сделай селфи при дневном свете. Лина увидит увлажнение, тон, поры и сразу подберёт ритуал под твою кожу сегодня.',
    ),
    _Slide(
      icon: Icons.auto_awesome_rounded,
      iconAccent: AppColors.roseDeep,
      eyebrow: 'Шаг 2',
      title: 'Получи свой уход',
      body:
          'На главной появится «Сегодня · ритуал» — утро и вечер по шагам. Отмечай галочками что сделала, копится streak.',
    ),
    _Slide(
      icon: Icons.chat_bubble_rounded,
      iconAccent: AppColors.gold,
      eyebrow: 'Шаг 3',
      title: 'Спроси Лину',
      body:
          'Не понятно про средство, ингредиент или реакцию? Тап по «Лина · диалог» — она ответит, учитывая твой профиль и последний скан.',
    ),
  ];

  bool get _isLast => _index == _slides.length - 1;

  void _next() {
    if (_isLast) {
      widget.onFinish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.sunrise)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                  child: Row(
                    children: [
                      _Dots(count: _slides.length, active: _index),
                      const Spacer(),
                      if (!_isLast)
                        TextButton(
                          onPressed: widget.onFinish,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                          ),
                          child: const Text('Пропустить'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemCount: _slides.length,
                    itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                  child: AppButton(
                    label: _isLast ? 'Начать' : 'Дальше',
                    onPressed: _next,
                    trailingIcon: _isLast
                        ? Icons.spa_rounded
                        : Icons.arrow_forward_rounded,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.icon,
    required this.iconAccent,
    required this.eyebrow,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color iconAccent;
  final String eyebrow;
  final String title;
  final String body;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  slide.iconAccent.withOpacity(0.18),
                  slide.iconAccent.withOpacity(0.32),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: slide.iconAccent.withOpacity(0.28),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(slide.icon, size: 44, color: slide.iconAccent),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            slide.eyebrow.toUpperCase(),
            style: AppTypography.eyebrow(color: AppColors.roseDeep),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(slide.title, style: AppTypography.display),
          const SizedBox(height: AppSpacing.md),
          Text(
            slide.body,
            style: AppTypography.bodySecondary.copyWith(fontSize: 16),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        final on = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          margin: const EdgeInsets.only(right: 6),
          width: on ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: on
                ? AppColors.roseDeep
                : AppColors.primaryAccent.withOpacity(0.32),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}
