import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';

/// Story-of-your-skin timeline: scans and routines interleaved by date with
/// stats up top. Tapping a routine card shows a sheet with its diff/adherence
/// and a "Сделать активной" CTA that clones the routine to the top of the
/// list so the Today screen picks it up.
class RoutineHistoryScreen extends ConsumerStatefulWidget {
  const RoutineHistoryScreen({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  ConsumerState<RoutineHistoryScreen> createState() =>
      _RoutineHistoryScreenState();
}

class _RoutineHistoryScreenState
    extends ConsumerState<RoutineHistoryScreen> {
  late Future<RoutineTimeline> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(backendApiProvider).getRoutinesTimeline();
  }

  void _reload() {
    setState(() {
      _future = ref.read(backendApiProvider).getRoutinesTimeline();
    });
  }

  Future<void> _resume(TimelineNode node) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(backendApiProvider).resumeRoutine(node.id!);
      messenger.showSnackBar(
        const SnackBar(content: Text('Рутина снова активна')),
      );
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.blush)),
          SafeArea(
            child: Column(
              children: [
                _Header(onBack: widget.onBack),
                Expanded(
                  child: FutureBuilder<RoutineTimeline>(
                    future: _future,
                    builder: (_, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primaryAccent),
                        );
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Не удалось загрузить.\n${snap.error}',
                            style: AppTypography.bodySecondary,
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      final tl = snap.data!;
                      if (tl.nodes.isEmpty) {
                        return const _Empty();
                      }
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                            AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
                        children: [
                          _StatsHeader(timeline: tl),
                          const SizedBox(height: AppSpacing.md),
                          for (final n in tl.nodes)
                            _TimelineRow(
                              node: n,
                              onResume: n.type == 'routine' && !n.isActive
                                  ? () => _resume(n)
                                  : null,
                            ),
                        ],
                      );
                    },
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

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EyebrowText('История', color: AppColors.roseDeep),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'Мои ',
                        style: AppTypography.h1.copyWith(fontSize: 26)),
                    TextSpan(
                      text: 'уходы',
                      style: AppTypography.serifItalic(fontSize: 26),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.timeline});
  final RoutineTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final adh = timeline.lastAdherence;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          _Stat(
            value: '${timeline.totalRoutines}',
            label: 'уход${_routineSuffix(timeline.totalRoutines)}',
          ),
          _StatDivider(),
          _Stat(
            value: '${timeline.currentStreakDays}',
            label: 'д${_streakSuffix(timeline.currentStreakDays)} подряд',
          ),
          _StatDivider(),
          _Stat(
            value: adh == null ? '—' : '${adh.percent}%',
            label:
                adh == null ? 'без данных' : '${adh.completedDays}/${adh.totalDays} дн.',
            tint: adh == null
                ? AppColors.textSecondary
                : adh.percent >= 70
                    ? AppColors.success
                    : adh.percent >= 30
                        ? Colors.orange
                        : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  static String _routineSuffix(int n) {
    final m = n % 100;
    if (m >= 11 && m <= 14) return 'ов';
    switch (n % 10) {
      case 1:
        return '';
      case 2:
      case 3:
      case 4:
        return 'а';
      default:
        return 'ов';
    }
  }

  static String _streakSuffix(int n) {
    final m = n % 100;
    if (m >= 11 && m <= 14) return 'ней';
    switch (n % 10) {
      case 1:
        return 'ень';
      case 2:
      case 3:
      case 4:
        return 'ня';
      default:
        return 'ней';
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.tint});
  final String value;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.h1.copyWith(
              fontSize: 22,
              color: tint ?? AppColors.roseDeep,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: AppColors.divider,
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.node, this.onResume});
  final TimelineNode node;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    switch (node.type) {
      case 'month_divider':
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, 8),
          child: EyebrowText(node.label ?? '', color: AppColors.textSecondary),
        );
      case 'scan':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _ScanDot(node: node),
        );
      case 'routine':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _RoutineCard(node: node, onResume: onResume),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _ScanDot extends StatelessWidget {
  const _ScanDot({required this.node});
  final TimelineNode node;

  @override
  Widget build(BuildContext context) {
    final score = node.scanScore ?? 0;
    final delta = node.scanDeltaVsPrev;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryAccent.withOpacity(0.18),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.roseDeep.withOpacity(0.25)),
          ),
          child: const Icon(Icons.camera_alt_rounded,
              size: 14, color: AppColors.roseDeep),
        ),
        const SizedBox(width: 12),
        Text(
          'Скан · ',
          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
        ),
        Text(
          'Score $score',
          style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
        ),
        if (delta != null && delta != 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (delta > 0 ? AppColors.success : Colors.orange)
                  .withOpacity(0.14),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${delta > 0 ? '+' : ''}$delta',
              style: AppTypography.caption.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: delta > 0 ? AppColors.success : Colors.orange,
              ),
            ),
          ),
        ],
        const Spacer(),
        Text(
          _shortDate(node.createdAt),
          style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({required this.node, this.onResume});
  final TimelineNode node;
  final VoidCallback? onResume;

  static const _sourceLabel = {
    'standard': 'Быстрый',
    'lina': 'Лина',
    'from_shelf': 'Из полки',
    'derm': 'Дерматолог',
  };

  @override
  Widget build(BuildContext context) {
    final source = _sourceLabel[node.kind] ?? 'Уход';
    final adh = node.adherence;
    final stepsCount = (node.morningCount ?? 0) + (node.eveningCount ?? 0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: node.isActive
              ? AppColors.roseDeep.withOpacity(0.45)
              : AppColors.divider,
          width: node.isActive ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pill(label: source, tone: _PillTone.primary),
              const SizedBox(width: 6),
              if (node.isActive)
                _Pill(label: 'Сейчас', tone: _PillTone.success),
              const Spacer(),
              Text(
                _shortDate(node.createdAt),
                style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            node.skinSummary?.isNotEmpty == true
                ? node.skinSummary!
                : node.stepsPreview?.isNotEmpty == true
                    ? node.stepsPreview!
                    : '$stepsCount шаг${_stepSuffix(stepsCount)}',
            style: AppTypography.body
                .copyWith(fontWeight: FontWeight.w600, height: 1.3),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (node.skinSummary?.isNotEmpty == true &&
              node.stepsPreview?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              node.stepsPreview!,
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (adh != null)
                _Pill(
                  label: '${adh.completedDays}/${adh.totalDays} дн · ${adh.percent}%',
                  tone: adh.percent >= 70
                      ? _PillTone.success
                      : adh.percent >= 30
                          ? _PillTone.warn
                          : _PillTone.muted,
                ),
              if (node.skinScoreBefore != null && node.skinScoreAfter != null)
                _Pill(
                  label:
                      'Score ${node.skinScoreBefore} → ${node.skinScoreAfter}',
                  tone: (node.skinScoreAfter! >= node.skinScoreBefore!)
                      ? _PillTone.success
                      : _PillTone.warn,
                ),
            ],
          ),
          if (node.diffAdded.isNotEmpty || node.diffRemoved.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final added in node.diffAdded)
              _DiffRow(text: added, added: true),
            for (final removed in node.diffRemoved)
              _DiffRow(text: removed, added: false),
          ],
          if (onResume != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onResume,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Сделать активной'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.roseDeep,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _stepSuffix(int n) {
    final m = n % 100;
    if (m >= 11 && m <= 14) return 'ов';
    switch (n % 10) {
      case 1:
        return '';
      case 2:
      case 3:
      case 4:
        return 'а';
      default:
        return 'ов';
    }
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.text, required this.added});
  final String text;
  final bool added;

  @override
  Widget build(BuildContext context) {
    final color = added ? AppColors.success : Colors.orange;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            added ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySm.copyWith(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

enum _PillTone { primary, success, warn, muted }

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tone});
  final String label;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _PillTone.primary => (
          AppColors.primary,
          AppColors.roseDeep,
        ),
      _PillTone.success => (
          AppColors.success.withOpacity(0.14),
          AppColors.success,
        ),
      _PillTone.warn => (
          Colors.orange.withOpacity(0.14),
          Colors.orange,
        ),
      _PillTone.muted => (
          AppColors.divider,
          AppColors.textSecondary,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🪞', style: TextStyle(fontSize: 48)),
            const SizedBox(height: AppSpacing.md),
            Text('Уходов ещё нет', style: AppTypography.h2),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Сделай первую рекомендацию — она появится здесь.',
              style: AppTypography.bodySecondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _shortDate(DateTime? dt) {
  if (dt == null) return '';
  const months = [
    '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
  ];
  final l = dt.toLocal();
  return '${l.day} ${months[l.month]}';
}
