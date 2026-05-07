import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';
import '../../scan/presentation/scan_result_screen.dart';
import '../domain/progress.dart';

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({
    super.key,
    required this.onBack,
    required this.onScan,
  });

  final VoidCallback onBack;
  final VoidCallback onScan;

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  int _days = 30;
  Future<ProgressData>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = ref.read(backendApiProvider).getProgress(days: _days);
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(backendApiProvider);
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
                _RangeTabs(
                  days: _days,
                  onPick: (d) {
                    setState(() => _days = d);
                    _reload();
                  },
                ),
                Expanded(
                  child: FutureBuilder<ProgressData>(
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
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Text(
                              'Не удалось загрузить.\n${snap.error}',
                              style: AppTypography.bodySecondary,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      final data = snap.data!;
                      if (data.points.isEmpty) {
                        return _Empty(onScan: widget.onScan);
                      }
                      return _Body(data: data, api: api);
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
                const EyebrowText('Прогресс', color: AppColors.roseDeep),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'Твоя ',
                        style:
                            AppTypography.h1.copyWith(fontSize: 26)),
                    TextSpan(
                      text: 'история',
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

class _RangeTabs extends StatelessWidget {
  const _RangeTabs({required this.days, required this.onPick});
  final int days;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    const opts = [(7, 'Неделя'), (30, 'Месяц'), (90, '3 месяца')];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 4, AppSpacing.lg, AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: opts.map((o) {
            final active = o.$1 == days;
            return Expanded(
              child: GestureDetector(
                onTap: () => onPick(o.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? AppColors.roseDeep : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    o.$2,
                    style: AppTypography.caption.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: active ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data, required this.api});
  final ProgressData data;
  final BackendApi api;

  @override
  Widget build(BuildContext context) {
    final byNewest = [...data.points]..sort((a, b) => b.date.compareTo(a.date));
    final byOldest = [...data.points]..sort((a, b) => a.date.compareTo(b.date));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
      children: [
        _ScoreOverview(stats: data.stats),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EyebrowText('Индекс кожи'),
              const SizedBox(height: 14),
              SizedBox(
                height: 140,
                child: _LineChart(
                  points: byOldest,
                  color: AppColors.roseDeep,
                  metric: (p) => p.score,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _MiniMetricsGrid(points: byOldest),
        const SizedBox(height: AppSpacing.lg),
        const EyebrowText('Фото-дневник'),
        const SizedBox(height: AppSpacing.sm),
        _PhotoDiary(points: byNewest, api: api),
      ],
    );
  }
}

class _ScoreOverview extends StatelessWidget {
  const _ScoreOverview({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final delta = stats.delta;
    final deltaColor = delta == null
        ? AppColors.textSecondary
        : (delta >= 0 ? AppColors.success : AppColors.warning);
    final deltaIcon = delta == null
        ? Icons.remove_rounded
        : (delta >= 0
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded);

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
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EyebrowText('Сейчас'),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${stats.latestScore ?? '—'}',
                      style: AppTypography.display.copyWith(
                        fontSize: 48,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('/ 100',
                          style: AppTypography.caption),
                    ),
                  ],
                ),
                if (delta != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(deltaIcon, size: 14, color: deltaColor),
                      const SizedBox(width: 4),
                      Text(
                        '${delta > 0 ? '+' : ''}$delta за период',
                        style: AppTypography.caption.copyWith(
                          color: deltaColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: 1,
            height: 64,
            color: AppColors.divider,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatRow(
                      label: 'Сканов',
                      value: '${stats.scansInWindow}'),
                  const SizedBox(height: 8),
                  _StatRow(
                      label: 'Серия',
                      value: '${stats.completionStreak} ${_dayWord(stats.completionStreak)}'),
                  const SizedBox(height: 8),
                  _StatRow(
                      label: 'Всего',
                      value: '${stats.scansTotal}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _dayWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: AppTypography.caption.copyWith(fontSize: 12)),
        ),
        Text(
          value,
          style: AppTypography.bodySm.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _MiniMetricsGrid extends StatelessWidget {
  const _MiniMetricsGrid({required this.points});
  final List<ProgressPoint> points;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          Expanded(
            child: _MiniMetric(
              points: points,
              label: 'Увлажнение',
              color: AppColors.info,
              metric: (p) => p.hydration,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniMetric(
              points: points,
              label: 'Себум',
              color: AppColors.gold,
              metric: (p) => p.sebum,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _MiniMetric(
              points: points,
              label: 'Тон',
              color: AppColors.primaryAccent,
              metric: (p) => p.tone,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniMetric(
              points: points,
              label: 'Поры',
              color: AppColors.roseDeep,
              metric: (p) => p.pores,
            ),
          ),
        ]),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.points,
    required this.label,
    required this.color,
    required this.metric,
  });
  final List<ProgressPoint> points;
  final String label;
  final Color color;
  final int Function(ProgressPoint) metric;

  @override
  Widget build(BuildContext context) {
    final last = points.isNotEmpty ? metric(points.last) : 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(label,
                  style:
                      AppTypography.caption.copyWith(fontSize: 12)),
              const Spacer(),
              Text(
                '$last',
                style: AppTypography.h3.copyWith(
                  fontSize: 18,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: _LineChart(
              points: points,
              color: color,
              metric: metric,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.points,
    required this.color,
    required this.metric,
    this.compact = false,
  });

  final List<ProgressPoint> points;
  final Color color;
  final int Function(ProgressPoint) metric;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(
        points: points,
        color: color,
        metric: metric,
        compact: compact,
      ),
      size: Size.infinite,
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.color,
    required this.metric,
    required this.compact,
  });

  final List<ProgressPoint> points;
  final Color color;
  final int Function(ProgressPoint) metric;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final values = points.map(metric).toList();
    final maxV = math.max(100, values.reduce(math.max));
    final minV = compact
        ? math.min(0, values.reduce(math.min)).toDouble()
        : math.max(0.0, (values.reduce(math.min) - 10).toDouble());
    final range = (maxV - minV).clamp(1, 100).toDouble();

    final pad = compact ? 4.0 : 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    Offset toPx(int i) {
      final x = points.length <= 1
          ? size.width / 2
          : pad + (i / (points.length - 1)) * w;
      final y = pad + h - ((values[i] - minV) / range) * h;
      return Offset(x, y);
    }

    if (!compact) {
      // Dotted gridlines (4 horizontal lines)
      final grid = Paint()
        ..color = AppColors.dividerStrong.withOpacity(0.4)
        ..strokeWidth = 0.5;
      for (var i = 0; i <= 4; i++) {
        final y = pad + (h * i / 4);
        for (var x = pad; x < pad + w; x += 6) {
          canvas.drawLine(Offset(x, y), Offset(x + 3, y), grid);
        }
      }
    }

    // Smooth curve
    final path = Path();
    final fill = Path();
    final pts = List.generate(points.length, toPx);
    if (pts.length == 1) {
      // single point — render a dot
      canvas.drawCircle(pts.first, 5, Paint()..color = color);
      return;
    }

    path.moveTo(pts.first.dx, pts.first.dy);
    fill.moveTo(pts.first.dx, size.height - pad);
    fill.lineTo(pts.first.dx, pts.first.dy);

    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final c1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final c2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p1.dx, p1.dy);
      fill.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p1.dx, p1.dy);
    }
    fill.lineTo(pts.last.dx, size.height - pad);
    fill.close();

    // Glow under curve
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.25), color.withOpacity(0)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    // Curve
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = compact ? 1.6 : 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke);

    // End dot
    final endDot = Paint()..color = color;
    canvas.drawCircle(pts.last, compact ? 2.5 : 4, endDot);
    canvas.drawCircle(
      pts.last,
      compact ? 5 : 8,
      Paint()..color = color.withOpacity(0.18),
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.points != points || old.color != color;
}

class _PhotoDiary extends StatelessWidget {
  const _PhotoDiary({required this.points, required this.api});
  final List<ProgressPoint> points;
  final BackendApi api;

  Future<void> _openScan(BuildContext context, ProgressPoint p) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryAccent),
      ),
    );
    try {
      final scan = await api.getScan(p.id);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (ctx) => ScanResultScreen(
            scan: scan,
            onBack: () => Navigator.of(ctx).pop(),
            onAccept: () => Navigator.of(ctx).pop(),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить скан: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final withPhotos = points.where((p) => p.hasPhoto).toList();
    if (withPhotos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          'Сканы без фото — только метрики.',
          style: AppTypography.bodySecondary.copyWith(fontSize: 13),
        ),
      );
    }

    final headers = api.imageAuthHeaders();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: withPhotos.length,
      itemBuilder: (ctx, i) {
        final p = withPhotos[i];
        return GestureDetector(
          onTap: () => _openScan(ctx, p),
          child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                api.scanPhotoUrl(p.id),
                headers: headers,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.primary,
                  child: const Icon(Icons.broken_image_rounded,
                      color: AppColors.roseDeep),
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _short(p.date),
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${p.score}',
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        );
      },
    );
  }

  static String _short(DateTime d) {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    final l = d.toLocal();
    return '${l.day} ${months[l.month]}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onScan});
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📈', style: TextStyle(fontSize: 56)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'История появится после первого скана',
            style: AppTypography.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Сделай селфи — увидишь динамику метрик и фото-дневник.',
            style: AppTypography.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: 220,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: Text('Сделать скан', style: AppTypography.button),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.roseDeep,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
