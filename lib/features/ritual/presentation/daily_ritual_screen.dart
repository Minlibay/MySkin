import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../../core/widgets/lina_avatar.dart';
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
      final fresh = await api.getToday();
      if (!mounted) return;
      setState(() => _today = fresh);
    } catch (e) {
      if (!mounted) return;
      setState(() => _today = t);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMorning = _phaseTab == 'morning';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: GlowBackground(
              variant:
                  isMorning ? GlowVariant.sunrise : GlowVariant.deep,
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

  bool get _isMorning => phaseTab == 'morning';

  List<TodayStep> get _steps =>
      _isMorning ? today.morning : today.evening;

  int get _done => _isMorning ? today.morningDone : today.eveningDone;

  int get _total => _steps.length;

  /// Index in the visible list of the next not-yet-done step, or -1 when the
  /// phase is fully complete. Drives the highlighted card + the sticky CTA.
  int get _activeIdx => _steps.indexWhere((s) => !s.done);

  @override
  Widget build(BuildContext context) {
    final activeIdx = _activeIdx;
    final hasActive = activeIdx >= 0;
    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            hasActive ? 110 : AppSpacing.xxl,
          ),
          children: [
            _Header(
              isMorning: _isMorning,
              onBack: onBack,
              onTogglePhase: () =>
                  onPhaseTab(_isMorning ? 'evening' : 'morning'),
            ),
            const SizedBox(height: AppSpacing.md),
            _Title(isMorning: _isMorning, total: _total),
            const SizedBox(height: AppSpacing.lg),
            _ProgressHero(
              done: _done,
              total: _total,
              nextTitle: hasActive ? _steps[activeIdx].title : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            ..._buildSteps(activeIdx),
            const SizedBox(height: AppSpacing.md),
            if (today.streak > 0) _StreakBadge(streak: today.streak),
            if (today.streak > 0) const SizedBox(height: AppSpacing.md),
            _LinaNote(isMorning: _isMorning),
            if (onScan != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ScanCta(onTap: onScan!),
            ],
          ],
        ),
        if (hasActive)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _StickyCta(
              order: activeIdx + 1,
              onTap: () => onToggle(_steps[activeIdx]),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildSteps(int activeIdx) {
    final out = <Widget>[];
    for (var i = 0; i < _steps.length; i++) {
      out.add(_StepCard(
        step: _steps[i],
        order: i + 1,
        state: _steps[i].done
            ? _StepState.done
            : (i == activeIdx ? _StepState.active : _StepState.upcoming),
        onTap: () => onToggle(_steps[i]),
      ));
      if (i < _steps.length - 1) out.add(const SizedBox(height: 8));
    }
    return out;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isMorning,
    required this.onBack,
    required this.onTogglePhase,
  });

  final bool isMorning;
  final VoidCallback onBack;
  final VoidCallback onTogglePhase;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
              child: const Icon(Icons.arrow_back_ios_new, size: 16),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child:
              EyebrowText(_dateLabel(), color: AppColors.roseDeep),
        ),
        Material(
          color: Colors.white.withOpacity(0.7),
          shape: const StadiumBorder(
              side: BorderSide(color: AppColors.divider)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTogglePhase,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isMorning
                        ? Icons.wb_sunny_rounded
                        : Icons.nightlight_round,
                    size: 14,
                    color: AppColors.roseDeep,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isMorning ? 'Утро' : 'Вечер',
                    style: AppTypography.bodySm.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _dateLabel() {
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    final d = DateTime.now();
    return '${isMorning ? "Утро" : "Вечер"} · ${d.day} ${months[d.month]}';
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.isMorning, required this.total});
  final bool isMorning;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: isMorning ? 'Утренний ' : 'Вечерний ',
              style: AppTypography.h1.copyWith(fontSize: 34, height: 1.05),
            ),
            TextSpan(
              text: 'ритуал',
              style: AppTypography.serifItalic(fontSize: 34),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Text(
          '$total ${_stepWord(total)} · подобрано Линой под твою кожу',
          style: AppTypography.caption.copyWith(fontSize: 13),
        ),
      ],
    );
  }

  String _stepWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'шаг';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'шага';
    return 'шагов';
  }
}

class _ProgressHero extends StatelessWidget {
  const _ProgressHero({
    required this.done,
    required this.total,
    required this.nextTitle,
  });
  final int done;
  final int total;
  final String? nextTitle;

  String _moodLabel() {
    if (total == 0) return 'Подбираем ритуал…';
    if (done == 0) return 'Начнём.';
    if (done == total) return 'Готово!';
    if (done * 2 < total) return 'Запустилось.';
    if (done * 2 == total) return 'Половина пути.';
    return 'Финишная прямая.';
  }

  String _captionLabel() {
    if (total == 0) return '';
    if (done == total) return 'Все шаги сделаны. Береги результат.';
    return nextTitle == null
        ? 'Следующий шаг скоро.'
        : 'Следующий шаг — ${nextTitle!.toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, AppColors.primary],
        ),
        border: Border.all(color: AppColors.primaryAccent.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryAccent.withOpacity(0.25),
            blurRadius: 28,
            offset: const Offset(0, 12),
            spreadRadius: -10,
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              tween: Tween(
                  begin: 0, end: total == 0 ? 0.0 : done / total),
              builder: (_, t, __) => Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(72, 72),
                    painter: _RingPainter(progress: t),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$done', style: AppTypography.h2.copyWith(height: 1)),
                      const SizedBox(height: 2),
                      Text(
                        'ИЗ $total',
                        style: AppTypography.eyebrow().copyWith(fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EyebrowText('Прогресс', color: AppColors.textSecondary),
                const SizedBox(height: 4),
                Text(
                  _moodLabel(),
                  style: AppTypography.h2.copyWith(fontSize: 22),
                ),
                if (_captionLabel().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _captionLabel(),
                    style: AppTypography.caption.copyWith(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width / 2) - 3;
    final track = Paint()
      ..color = AppColors.primaryAccent.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(c, r, track);
    final stroke = Paint()
      ..color = AppColors.roseDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      progress.clamp(0, 1) * 2 * math.pi,
      false,
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress;
}

enum _StepState { upcoming, active, done }

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.order,
    required this.state,
    required this.onTap,
  });

  final TodayStep step;
  final int order;
  final _StepState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = state == _StepState.active;
    final isDone = state == _StepState.done;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        gradient: isActive
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, Colors.white],
              )
            : null,
        color: isActive ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? AppColors.primaryAccent
              : AppColors.divider,
          width: isActive ? 1.2 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.primaryAccent.withOpacity(0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                  spreadRadius: -14,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Opacity(
            opacity: isDone ? 0.6 : 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Checkmark(done: isDone),
                  const SizedBox(width: 12),
                  _OrderBadge(order: order, isActive: isActive),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: AppTypography.bodyMedium.copyWith(
                            fontSize: 14,
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: AppColors.textSecondary,
                          ),
                        ),
                        if (step.explanation.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            step.explanation,
                            style: AppTypography.caption.copyWith(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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
                                        color: AppColors.primary
                                            .withOpacity(isActive ? 0.7 : 1),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
        color: done ? AppColors.roseDeep : Colors.transparent,
        border: done
            ? null
            : Border.all(color: AppColors.dividerStrong, width: 1.5),
      ),
      alignment: Alignment.center,
      child: done
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : null,
    );
  }
}

class _OrderBadge extends StatelessWidget {
  const _OrderBadge({required this.order, required this.isActive});
  final int order;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$order.',
      style: AppTypography.serifItalic(
        fontSize: 18,
        color: isActive ? AppColors.roseDeep : AppColors.textSecondary,
      ).copyWith(height: 1),
    );
  }
}

class _LinaNote extends StatelessWidget {
  const _LinaNote({required this.isMorning});
  final bool isMorning;

  static const _morningTips = [
    'Подожди 90 секунд между сывороткой и кремом — иначе активы не успеют проникнуть.',
    'SPF — последний шаг, перед выходом из дома, без исключений.',
    'Холодная вода после умывания — лучше любого тонера для сужения пор.',
  ];
  static const _eveningTips = [
    'Двойное очищение вечером убирает SPF и день — кожа дышит за ночь.',
    'Активы (ретинол, кислоты) лучше работают только вечером — днём они под SPF.',
    'Подушка влияет — переворачивай наволочку через ночь, помогает с акне.',
  ];

  @override
  Widget build(BuildContext context) {
    final tips = isMorning ? _morningTips : _eveningTips;
    final tip = tips[DateTime.now().day % tips.length];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.roseDeep.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.primaryAccent.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinaAvatar(size: 32, monogram: true, online: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'СОВЕТ ОТ ЛИНЫ',
                  style: AppTypography.eyebrow(color: AppColors.roseDeep),
                ),
                const SizedBox(height: 4),
                Text(
                  '«$tip»',
                  style: AppTypography.serifItalic(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ).copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.champagne, Colors.white],
        ),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            '$streak ${_dayWord(streak)} подряд',
            style: AppTypography.bodySm.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _dayWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }
}

class _StickyCta extends StatelessWidget {
  const _StickyCta({required this.order, required this.onTap});
  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withOpacity(0),
            AppColors.background,
          ],
          stops: const [0, 0.35],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
      child: Material(
        color: AppColors.roseDeep,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Отметить шаг $order выполненным',
                  style: AppTypography.button,
                ),
                const SizedBox(width: 8),
                const Icon(Icons.check_rounded,
                    size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanCta extends StatelessWidget {
  const _ScanCta({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: AppColors.surface,
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryAccent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.center_focus_strong_rounded,
                  color: AppColors.roseDeep,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Сделать скан сегодня',
                        style:
                            AppTypography.bodyMedium.copyWith(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      'Чтобы Лина увидела как кожа реагирует',
                      style: AppTypography.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
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
