import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';
import '../domain/today.dart';

class DailyRitualScreen extends ConsumerStatefulWidget {
  const DailyRitualScreen({
    super.key,
    required this.onBack,
    this.onScan,
  });
  final VoidCallback onBack;
  final VoidCallback? onScan;

  @override
  ConsumerState<DailyRitualScreen> createState() =>
      _DailyRitualScreenState();
}

class _DailyRitualScreenState extends ConsumerState<DailyRitualScreen> {
  Today? _today;
  String _phaseTab = 'morning';
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _phaseTab = DateTime.now().hour < 16 ? 'morning' : 'evening';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await ref.read(backendApiProvider).getToday();
      if (!mounted) return;
      setState(() {
        _today = t;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(TodayStep step) async {
    final t = _today;
    if (t == null) return;
    final api = ref.read(backendApiProvider);
    // optimistic
    setState(() => _today = t.withToggled(_phaseTab, step.index));
    try {
      if (step.done) {
        await api.uncheckStep(phase: _phaseTab, stepIndex: step.index);
      } else {
        await api.checkStep(
          phase: _phaseTab,
          stepIndex: step.index,
          stepTitle: step.title,
        );
      }
      // refresh streak & state
      final fresh = await api.getToday();
      if (!mounted) return;
      setState(() => _today = fresh);
    } catch (e) {
      // rollback
      if (!mounted) return;
      setState(() => _today = t);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: GlowBackground(
              variant: _phaseTab == 'morning'
                  ? GlowVariant.sunrise
                  : GlowVariant.deep,
            ),
          ),
          SafeArea(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryAccent),
                  )
                : _error != null
                    ? _ErrorPane(error: _error!, onRetry: _load)
                    : _today!.hasRoutine
                        ? _Body(
                            today: _today!,
                            phaseTab: _phaseTab,
                            onPhaseTab: (p) =>
                                setState(() => _phaseTab = p),
                            onBack: widget.onBack,
                            onToggle: _toggle,
                            onScan: widget.onScan,
                          )
                        : _Empty(
                            onBack: widget.onBack,
                            onScan: widget.onScan,
                          ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.today,
    required this.phaseTab,
    this.onScan,
    required this.onPhaseTab,
    required this.onBack,
    required this.onToggle,
  });

  final Today today;
  final String phaseTab;
  final ValueChanged<String> onPhaseTab;
  final VoidCallback onBack;
  final ValueChanged<TodayStep> onToggle;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final steps = phaseTab == 'morning' ? today.morning : today.evening;
    final done = phaseTab == 'morning' ? today.morningDone : today.eveningDone;
    final progress = steps.isEmpty ? 0.0 : done / steps.length;

    return Column(
      children: [
        _Header(
          today: today,
          phaseTab: phaseTab,
          onPhaseTab: onPhaseTab,
          onBack: onBack,
          progress: progress,
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
            itemCount: steps.length + (onScan != null ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              if (i == steps.length && onScan != null) {
                return _ScanCta(onTap: onScan!);
              }
              return _StepCard(
                step: steps[i],
                order: i + 1,
                total: steps.length,
                onTap: () => onToggle(steps[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ScanCta extends StatelessWidget {
  const _ScanCta({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, AppColors.primary],
              ),
              border: Border.all(
                  color: AppColors.primaryAccent.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryAccent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.center_focus_strong_rounded,
                    color: AppColors.roseDeep,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Сделать скан сегодня',
                          style: AppTypography.bodyMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Чтобы Лина увидела как кожа реагирует',
                        style:
                            AppTypography.caption.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    size: 20, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.today,
    required this.phaseTab,
    required this.onPhaseTab,
    required this.onBack,
    required this.progress,
  });

  final Today today;
  final String phaseTab;
  final ValueChanged<String> onPhaseTab;
  final VoidCallback onBack;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Material(
                  color: Colors.white.withOpacity(0.7),
                  shape: const CircleBorder(
                      side: BorderSide(color: AppColors.divider)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onBack,
                    child:
                        const Icon(Icons.arrow_back_ios_new, size: 16),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EyebrowText(_dateLabel(),
                        color: AppColors.roseDeep),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: 'Твой ',
                            style:
                                AppTypography.h1.copyWith(fontSize: 26)),
                        TextSpan(
                          text: 'ритуал',
                          style: AppTypography.serifItalic(fontSize: 26),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
              if (today.streak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.champagne, Colors.white],
                    ),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                        color: AppColors.gold.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 12, color: AppColors.gold),
                      const SizedBox(width: 4),
                      Text(
                        '${today.streak} ${_dayWord(today.streak)}',
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _PhaseTab(
                  active: phaseTab == 'morning',
                  icon: Icons.wb_sunny_rounded,
                  label: 'Утро',
                  count:
                      '${today.morningDone}/${today.morning.length}',
                  onTap: () => onPhaseTab('morning'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PhaseTab(
                  active: phaseTab == 'evening',
                  icon: Icons.nightlight_round,
                  label: 'Вечер',
                  count:
                      '${today.eveningDone}/${today.evening.length}',
                  onTap: () => onPhaseTab('evening'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 400),
              tween: Tween(begin: 0, end: progress),
              builder: (_, t, __) => LinearProgressIndicator(
                value: t,
                minHeight: 5,
                backgroundColor:
                    AppColors.primaryAccent.withOpacity(0.15),
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.roseDeep),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel() {
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    final d = DateTime.now();
    return '${d.day} ${months[d.month]}';
  }

  String _dayWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }
}

class _PhaseTab extends StatelessWidget {
  const _PhaseTab({
    required this.active,
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });
  final bool active;
  final IconData icon;
  final String label;
  final String count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color:
                active ? AppColors.surface : Colors.white.withOpacity(0.45),
            border: Border.all(
              color: active
                  ? AppColors.primaryAccent
                  : AppColors.divider,
              width: active ? 1.4 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.shadowCard,
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                      spreadRadius: -6,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: active
                      ? AppColors.roseDeep
                      : AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTypography.bodyMedium.copyWith(
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                count,
                style: AppTypography.eyebrow().copyWith(
                  fontSize: 11,
                  color: active
                      ? AppColors.roseDeep
                      : AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.order,
    required this.total,
    required this.onTap,
  });
  final TodayStep step;
  final int order;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: step.done
                ? AppColors.success.withOpacity(0.08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: step.done
                  ? AppColors.success.withOpacity(0.5)
                  : AppColors.divider,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Checkmark(done: step.done),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Шаг $order из $total',
                      style: AppTypography.eyebrow().copyWith(fontSize: 10),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.title,
                      style: AppTypography.h3.copyWith(
                        decoration: step.done
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: AppColors.textSecondary,
                        color: step.done
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (step.ingredients.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: step.ingredients
                            .take(3)
                            .map((i) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius:
                                        BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    i,
                                    style: AppTypography.caption.copyWith(
                                      fontSize: 11,
                                      color: AppColors.roseDeep,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                    if (step.explanation.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        step.explanation,
                        style: AppTypography.bodySm.copyWith(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Checkmark extends StatelessWidget {
  const _Checkmark({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.success : Colors.transparent,
        border: done
            ? null
            : Border.all(color: AppColors.dividerStrong, width: 1.5),
      ),
      alignment: Alignment.center,
      child: done
          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
          : null,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onBack, this.onScan});
  final VoidCallback onBack;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🌸', style: TextStyle(fontSize: 56)),
          const SizedBox(height: AppSpacing.md),
          Text('Ритуал ещё не подобран',
              style: AppTypography.h2, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Сделай первую рекомендацию — Лина соберёт утро и вечер.',
            style: AppTypography.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (onScan != null)
            SizedBox(
              width: 220,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.center_focus_strong_rounded),
                label: const Text('Сделать скан'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.roseDeep,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          TextButton(
            onPressed: onBack,
            child: const Text('Вернуться'),
          ),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.warning),
            const SizedBox(height: AppSpacing.md),
            Text('Не удалось загрузить план дня',
                style: AppTypography.body, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onRetry, child: const Text('Ещё раз')),
          ],
        ),
      ),
    );
  }
}
