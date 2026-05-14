import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../../core/widgets/selection_card.dart';
import '../../ai/domain/models.dart';
import '../domain/onboarding_step.dart';
import 'onboarding_controller.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key, required this.onComplete});
  final void Function(SkinProfile profile) onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final ctrl = ref.read(onboardingControllerProvider.notifier);

    if (state.isDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onComplete(state.profile);
      });
    }

    final step = OnboardingFlow.stepFor(state.currentStep);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: GlowBackground(variant: GlowVariant.sunrise),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                  child: Row(
                    children: [
                      if (state.history.length > 1)
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: Material(
                            color: Colors.white.withOpacity(0.7),
                            shape: const CircleBorder(
                              side: BorderSide(color: AppColors.divider),
                            ),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: ctrl.back,
                              child: const Icon(Icons.arrow_back_ios_new,
                                  size: 16),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 40),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm),
                          child: _ProgressDots(
                            current: state.history.length - 1,
                            total: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, anim) {
                final offset = Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(anim);
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: _StepView(
                key: ValueKey(step.id),
                step: step,
                profile: state.profile,
                controller: ctrl,
              ),
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

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i <= current;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 3,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.roseDeep
                  : AppColors.textPrimary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        );
      }),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({
    super.key,
    required this.step,
    required this.profile,
    required this.controller,
  });

  final OnboardingStep step;
  final SkinProfile profile;
  final OnboardingController controller;

  String? get _selectedSingle {
    switch (step.id) {
      case OnboardingStepId.skinType:
      case OnboardingStepId.skinTypeHelp:
        return profile.skinType;
      case OnboardingStepId.pores:
        return profile.pores;
      case OnboardingStepId.acneType:
        return profile.acneType;
      case OnboardingStepId.sensitivity:
        return profile.sensitivity;
      case OnboardingStepId.sensitivityReaction:
        return profile.sensitivityReaction;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepNum = _stepNumberFor(step.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stepNum != null)
            EyebrowText('Шаг $stepNum · из 06', color: AppColors.roseDeep),
          // total = 6 steps after budget removal — counter renumbered below
          if (stepNum != null) const SizedBox(height: 10),
          _StepTitle(title: step.title),
          if (step.subtitle != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              step.subtitle!,
              style: AppTypography.bodySecondary.copyWith(fontSize: 15),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: step.isTextInput
                ? _TextInputStep(step: step, controller: controller)
                : step.multiSelect
                    ? _buildMulti()
                    : _buildSingle(),
          ),
          if (step.multiSelect)
            AppButton(
              label: 'Продолжить',
              onPressed: profile.concerns.isEmpty
                  ? null
                  : controller.confirmMulti,
            ),
        ],
      ),
    );
  }

  int? _stepNumberFor(OnboardingStepId id) => switch (id) {
        OnboardingStepId.name => 1,
        OnboardingStepId.gender => 2,
        OnboardingStepId.skinType => 3,
        OnboardingStepId.skinTypeHelp => 3,
        OnboardingStepId.pores => 4,
        OnboardingStepId.concerns => 4,
        OnboardingStepId.acneType => 5,
        OnboardingStepId.sensitivity => 5,
        OnboardingStepId.sensitivityReaction => 6,
        OnboardingStepId.done => null,
      };

  Widget _buildSingle() {
    final selected = _selectedSingle;
    return ListView.separated(
      itemCount: step.options.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) {
        final opt = step.options[i];
        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 240 + i * 60),
          tween: Tween(begin: 0, end: 1),
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 12),
              child: child,
            ),
          ),
          child: SelectionCard(
            title: opt.title,
            subtitle: opt.subtitle,
            emoji: opt.emoji,
            selected: selected == opt.id,
            onTap: () => controller.selectSingle(opt.id),
          ),
        );
      },
    );
  }

  Widget _buildMulti() {
    return SingleChildScrollView(
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: step.options.map((opt) {
          final selected = profile.concerns.contains(opt.id);
          return AppChip(
            label: opt.title,
            selected: selected,
            onTap: () => controller.toggleMulti(opt.id),
          );
        }).toList(),
      ),
    );
  }
}

/// Headline that highlights certain words ("цели" / "имя" / "поры" / etc.)
/// in italic roseDeep — signature accent of the Glow / soft luxury system.
class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.title});
  final String title;

  static const _accents = {
    'цели', 'имя', 'тип', 'поры', 'улучшить', 'реагирует', 'бюджет',
    'зовут',
  };

  @override
  Widget build(BuildContext context) {
    // Dart's String.split() drops the delimiter even when it's a capturing
    // group — so the previous `title.split(RegExp(r'(\s+)'))` glued every
    // word together visually. Walk the string manually instead so the
    // whitespace runs survive between word spans.
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\s+');
    var cursor = 0;
    for (final m in pattern.allMatches(title)) {
      if (m.start > cursor) {
        spans.add(_styledWord(title.substring(cursor, m.start)));
      }
      spans.add(TextSpan(
        text: title.substring(m.start, m.end),
        style: AppTypography.display,
      ));
      cursor = m.end;
    }
    if (cursor < title.length) {
      spans.add(_styledWord(title.substring(cursor)));
    }
    return Text.rich(TextSpan(children: spans));
  }

  TextSpan _styledWord(String w) {
    final lower = w.toLowerCase().replaceAll(RegExp(r'[^а-яё]'), '');
    if (_accents.contains(lower)) {
      return TextSpan(
        text: w,
        style: AppTypography.serifItalic(fontSize: 36),
      );
    }
    return TextSpan(text: w, style: AppTypography.display);
  }
}

class _TextInputStep extends StatefulWidget {
  const _TextInputStep({required this.step, required this.controller});
  final OnboardingStep step;
  final OnboardingController controller;

  @override
  State<_TextInputStep> createState() => _TextInputStepState();
}

class _TextInputStepState extends State<_TextInputStep> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _ctrl.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: AppTypography.h2,
          decoration: InputDecoration(
            hintText: widget.step.placeholder,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide:
                  const BorderSide(color: AppColors.primaryAccent, width: 1.5),
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (v) {
            if (canSubmit) widget.controller.submitText(v);
          },
        ),
        const Spacer(),
        AppButton(
          label: 'Продолжить',
          onPressed:
              canSubmit ? () => widget.controller.submitText(_ctrl.text) : null,
        ),
      ],
    );
  }
}
