import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/breathing_loader.dart';
import '../../../core/widgets/glow_background.dart';
import '../../../core/widgets/lina_avatar.dart';
import '../../ai/domain/models.dart';
import '../../routine/presentation/routine_screen.dart';
import '../domain/derm_state.dart';
import 'derm_state_machine_controller.dart';

class Derm2Screen extends ConsumerStatefulWidget {
  const Derm2Screen({
    super.key,
    required this.profile,
    this.onBack,
  });
  final SkinProfile profile;
  final VoidCallback? onBack;

  @override
  ConsumerState<Derm2Screen> createState() => _Derm2ScreenState();
}

class _Derm2ScreenState extends ConsumerState<Derm2Screen> {
  final _answerController = TextEditingController();
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_started) {
        _started = true;
        ref
            .read(dermControllerProvider.notifier)
            .start(widget.profile);
      }
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dermControllerProvider);
    final ctrl = ref.read(dermControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.blush)),
          SafeArea(
            child: Column(
              children: [
                _LinaHeader(
                  onBack:
                      widget.onBack ?? () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildPhase(state, ctrl),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhase(
      DermState state, DermStateMachineController ctrl) {
    switch (state.phase) {
      case DermPhase.init:
      case DermPhase.collectingData:
      case DermPhase.analyzing:
      case DermPhase.collectingClarification:
        return _LoadingPane(
          key: const ValueKey('loading'),
          label: 'AI анализирует твою кожу...',
        );
      case DermPhase.generatingRoutine:
      case DermPhase.readyToRecommend:
        return _LoadingPane(
          key: const ValueKey('generating'),
          label: 'Создаём персональную формулу...',
        );
      case DermPhase.needClarification:
        return _ClarificationPane(
          key: const ValueKey('clarify'),
          state: state,
          controller: _answerController,
          onSubmit: (txt) {
            _answerController.clear();
            ctrl.submitClarification(txt);
          },
        );
      case DermPhase.showResult:
      case DermPhase.followUp:
        if (state.result == null) {
          return _LoadingPane(
              key: const ValueKey('wait'), label: 'Готовим результат...');
        }
        return _ResultPane(
          key: const ValueKey('result'),
          state: state,
          onFollowUp: (msg) => ctrl.submitFollowUp(msg),
        );
      case DermPhase.error:
        return _ErrorPane(
          key: const ValueKey('error'),
          message: state.errorMessage ?? 'Что-то пошло не так.',
          onRetry: () => ctrl.start(widget.profile),
        );
    }
  }
}

class _LinaHeader extends StatelessWidget {
  const _LinaHeader({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      child: Row(
        children: [
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
                onTap: onBack,
                child:
                    const Icon(Icons.arrow_back_ios_new, size: 16),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const LinaAvatar(size: 40),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Лина', style: AppTypography.h2.copyWith(fontSize: 19)),
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'твой AI-помощник',
                      style: AppTypography.caption.copyWith(
                          fontSize: 11, color: AppColors.success),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingPane extends StatelessWidget {
  const _LoadingPane({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const BreathingLoader(),
        const SizedBox(height: AppSpacing.lg),
        Text(label, style: AppTypography.body),
      ],
    );
  }
}

class _ClarificationPane extends StatelessWidget {
  const _ClarificationPane({
    super.key,
    required this.state,
    required this.controller,
    required this.onSubmit,
  });

  final DermState state;
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.confidence != null)
            _ConfidenceBar(value: state.confidence!),
          const SizedBox(height: AppSpacing.md),
          Text('AI хочет уточнить', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.xs),
          AppCard(
            child: Text(
              state.pendingQuestion ?? '',
              style: AppTypography.h2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: TextField(
              controller: controller,
              maxLines: 3,
              minLines: 1,
              autofocus: true,
              style: AppTypography.body,
              decoration: const InputDecoration(
                hintText: 'Расскажи своими словами...',
                border: InputBorder.none,
              ),
            ),
          ),
          const Spacer(),
          AppButton(
            label: 'Ответить',
            onPressed: () {
              final txt = controller.text.trim();
              if (txt.isEmpty) return;
              onSubmit(txt);
            },
          ),
        ],
      ),
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  const _ConfidenceBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Уверенность AI', style: AppTypography.caption),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.clamp(0, 1)),
              duration: const Duration(milliseconds: 400),
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: AppColors.primary,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primaryAccent),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text('${(value * 100).round()}%',
            style: AppTypography.caption.copyWith(
                color: AppColors.primaryAccent,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ResultPane extends StatelessWidget {
  const _ResultPane({
    super.key,
    required this.state,
    required this.onFollowUp,
  });
  final DermState state;
  final ValueChanged<String> onFollowUp;

  @override
  Widget build(BuildContext context) {
    return RoutineScreen(
      result: state.result!,
      onFollowUp: () => _openFollowUpSheet(context),
    );
  }

  void _openFollowUpSheet(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Что изменилось?', style: AppTypography.h2),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Опиши, что заметила — AI скорректирует уход.',
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: ctrl,
              maxLines: 4,
              minLines: 2,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Например: появилась сухость на щеках...',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Отправить',
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.isEmpty) return;
                Navigator.of(ctx).pop();
                onFollowUp(t);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 56, color: AppColors.danger),
          const SizedBox(height: AppSpacing.md),
          Text(message,
              style: AppTypography.body, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Попробовать снова', onPressed: onRetry),
        ],
      ),
    );
  }
}
