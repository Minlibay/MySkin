import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Apple Health-style ring indicator with serif numeral inside.
class MetricRing extends StatelessWidget {
  const MetricRing({
    super.key,
    required this.value,
    this.label,
    this.color,
    this.size = 78,
    this.suffix = '%',
    this.stroke = 6,
    this.animate = true,
  });

  final int value;
  final String? label;
  final Color? color;
  final double size;
  final String? suffix;
  final double stroke;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primaryAccent;
    final ring = SizedBox(
      width: size,
      height: size,
      child: animate
          ? TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOut,
              tween: Tween(begin: 0, end: value / 100),
              builder: (_, t, __) => CustomPaint(
                painter: _RingPainter(progress: t, color: c, stroke: stroke),
                child: _RingInner(value: value, size: size, suffix: suffix),
              ),
            )
          : CustomPaint(
              painter:
                  _RingPainter(progress: value / 100, color: c, stroke: stroke),
              child: _RingInner(value: value, size: size, suffix: suffix),
            ),
    );
    if (label == null) return ring;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ring,
        const SizedBox(height: 8),
        Text(
          label!,
          style: AppTypography.caption.copyWith(fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _RingInner extends StatelessWidget {
  const _RingInner({
    required this.value,
    required this.size,
    required this.suffix,
  });
  final int value;
  final double size;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: AppTypography.h2.copyWith(
              fontSize: size * 0.32,
              height: 1,
            ),
          ),
          if (suffix != null && suffix!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                suffix!,
                style: AppTypography.eyebrow(color: AppColors.textSecondary)
                    .copyWith(fontSize: 9),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.primaryAccent.withOpacity(0.15);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress.clamp(0.0, 1.0) * 2 * math.pi,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
