import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../../core/widgets/metric_ring.dart';
import '../../api/backend_api.dart';
import 'routine_screen.dart';

class RoutineHistoryScreen extends ConsumerStatefulWidget {
  const RoutineHistoryScreen({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  ConsumerState<RoutineHistoryScreen> createState() =>
      _RoutineHistoryScreenState();
}

class _RoutineHistoryScreenState
    extends ConsumerState<RoutineHistoryScreen> {
  late Future<List<RoutineRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(backendApiProvider).listRoutines();
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
                Padding(
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
                            onTap: widget.onBack,
                            child: const Icon(Icons.arrow_back_ios_new,
                                size: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const EyebrowText('История',
                                color: AppColors.roseDeep),
                            const SizedBox(height: 2),
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                    text: 'Мои ',
                                    style:
                                        AppTypography.h1.copyWith(fontSize: 26)),
                                TextSpan(
                                  text: 'уходы',
                                  style:
                                      AppTypography.serifItalic(fontSize: 26),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<RoutineRecord>>(
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
                      final items = snap.data ?? const [];
                      if (items.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🪞',
                                    style: TextStyle(fontSize: 48)),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'Уходов ещё нет',
                                  style: AppTypography.h2,
                                ),
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
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.md,
                            AppSpacing.lg,
                            AppSpacing.xxl),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) => _Row(
                          record: items[i],
                          onTap: () => _open(context, items[i]),
                        ),
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

  void _open(BuildContext context, RoutineRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => RoutineScreen(
          result: record.result,
          onBack: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.record, required this.onTap});
  final RoutineRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final score = record.result.skinScore;
    final isStandard = record.kind == 'standard';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              if (score != null)
                MetricRing(
                  value: score,
                  size: 56,
                  stroke: 5,
                  color: AppColors.roseDeep,
                  suffix: null,
                  animate: false,
                )
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                  child: const Icon(Icons.spa_rounded,
                      color: AppColors.roseDeep),
                ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isStandard
                                ? AppColors.primary
                                : AppColors.roseDeep.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            isStandard ? 'Быстрый' : 'Лина',
                            style: AppTypography.caption.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.roseDeep,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(_fmtDate(record.createdAt),
                            style: AppTypography.caption
                                .copyWith(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.result.skinSummary ??
                          '${record.result.morning.length} утром · '
                              '${record.result.evening.length} вечером',
                      style: AppTypography.bodySm,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime dt) {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    final l = dt.toLocal();
    return '${l.day} ${months[l.month]}';
  }
}
