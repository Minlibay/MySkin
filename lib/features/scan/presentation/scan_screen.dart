import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../api/backend_api.dart';
import '../domain/scan_result.dart';

/// Camera-styled screen with face mesh overlay. Uses gallery picker under
/// the hood (web doesn't have reliable camera access on iOS Safari).
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({
    super.key,
    required this.onBack,
    required this.onResult,
  });

  final VoidCallback onBack;
  final ValueChanged<ScanResult> onResult;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  String? _error;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
      );
      if (picked == null) {
        if (!mounted) return;
        setState(() => _busy = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      final b64 = base64Encode(bytes);
      final result = await ref.read(backendApiProvider).uploadScan(
            photoBase64: b64,
            mime: picked.mimeType ?? 'image/jpeg',
          );
      if (!mounted) return;
      widget.onResult(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не получилось загрузить: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0A0C),
      body: Stack(
        children: [
          // simulated camera surface
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.1,
                  colors: [
                    Color(0xFF5A3744),
                    Color(0xFF2A1A20),
                    Color(0xFF0F0A0C),
                  ],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
          ),
          // face mesh
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => CustomPaint(
                painter: _FaceMeshPainter(t: _pulse.value),
              ),
            ),
          ),
          // All controls in one Column flow inside SafeArea — top chrome at
          // the top, big headline below, shutter card pushed to the bottom
          // by the Spacer. No more positional ambiguity.
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  // Top chrome
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        _GlassButton(
                          icon: Icons.close_rounded,
                          onTap: widget.onBack,
                        ),
                        const Spacer(),
                        _LightStatusPill(),
                        const Spacer(),
                        _GlassButton(
                          icon: Icons.flash_on_rounded,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Headline
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Text(
                          'Чуть выше подбородок —\nи держи ровно',
                          textAlign: TextAlign.center,
                          style: AppTypography.serifItalic(
                            fontSize: 26,
                            color: Colors.white,
                          ).copyWith(height: 1.15),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Совмести овал лица с маркерами',
                          textAlign: TextAlign.center,
                          style: AppTypography.caption.copyWith(
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Pushes shutter to bottom.
                  const Spacer(),
                  // Bottom shutter card
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _busy
                                      ? 'Анализируем кожу…'
                                      : 'Анализ за 6 секунд',
                                  style: AppTypography.body.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _error ??
                                      '12 параметров · фото не покидает наш сервер',
                                  style: AppTypography.caption.copyWith(
                                    color: _error != null
                                        ? AppColors.warning
                                        : Colors.white.withOpacity(0.55),
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _ShutterButton(busy: _busy, onTap: _capture),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceMeshPainter extends CustomPainter {
  _FaceMeshPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.42;

    // outer dashed oval
    final ovalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.primaryAccent.withOpacity(0.55)
      ..strokeWidth = 1;
    final dash = Path();
    final ovalRect =
        Rect.fromCenter(center: Offset(cx, cy), width: 220, height: 300);
    _addDashedOval(dash, ovalRect, dashWidth: 4, dashSpace: 5);
    canvas.drawPath(dash, ovalPaint);

    // mesh strokes
    final mesh = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.primaryAccent.withOpacity(0.32)
      ..strokeWidth = 0.7;
    final paths = [
      Path()
        ..moveTo(cx - 80, cy - 60)
        ..quadraticBezierTo(cx, cy - 90, cx + 80, cy - 60),
      Path()
        ..moveTo(cx - 90, cy - 25)
        ..quadraticBezierTo(cx, cy - 45, cx + 90, cy - 25),
      Path()
        ..moveTo(cx - 80, cy + 30)
        ..quadraticBezierTo(cx, cy + 20, cx + 80, cy + 30),
      Path()
        ..moveTo(cx - 70, cy + 80)
        ..quadraticBezierTo(cx, cy + 80, cx + 70, cy + 80),
      Path()
        ..moveTo(cx - 80, cy - 60)
        ..lineTo(cx - 70, cy + 120),
      Path()
        ..moveTo(cx, cy - 90)
        ..lineTo(cx, cy + 130),
      Path()
        ..moveTo(cx + 80, cy - 60)
        ..lineTo(cx + 70, cy + 120),
    ];
    for (final p in paths) {
      canvas.drawPath(p, mesh);
    }

    // anchors
    final anchor = Paint()..color = AppColors.primaryAccent;
    final anchorPositions = [
      Offset(cx - 35, cy - 25),
      Offset(cx + 35, cy - 25),
      Offset(cx, cy + 25),
      Offset(cx - 28, cy + 80),
      Offset(cx + 28, cy + 80),
      Offset(cx, cy + 110),
    ];
    for (final p in anchorPositions) {
      canvas.drawCircle(p, 2.5, anchor);
    }

    // pulse ring
    final pulseR = 145 + 12 * (math.sin(t * 2 * math.pi) + 1) / 2;
    final pulseO = 0.2 + 0.5 * ((math.cos(t * 2 * math.pi) + 1) / 2);
    final pulse = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.primaryAccent.withOpacity(pulseO)
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset(cx, cy), pulseR, pulse);

    // corner brackets
    final cornerColor = AppColors.primaryAccent;
    final corners = [
      (cx - 130, cy - 150, 0.0),
      (cx + 130, cy - 150, 90.0),
      (cx - 130, cy + 200, 270.0),
      (cx + 130, cy + 200, 180.0),
    ];
    for (final c in corners) {
      canvas.save();
      canvas.translate(c.$1, c.$2);
      canvas.rotate(c.$3 * math.pi / 180);
      final cp = Paint()
        ..color = cornerColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(0, 0), const Offset(18, 0), cp);
      canvas.drawLine(const Offset(0, 0), const Offset(0, 18), cp);
      canvas.restore();
    }
  }

  void _addDashedOval(Path target, Rect rect,
      {required double dashWidth, required double dashSpace}) {
    final src = Path()..addOval(rect);
    for (final m in src.computeMetrics()) {
      var dist = 0.0;
      while (dist < m.length) {
        final next = math.min(dist + dashWidth, m.length);
        target.addPath(m.extractPath(dist, next), Offset.zero);
        dist = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FaceMeshPainter old) => old.t != t;
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.white.withOpacity(0.18),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _LightStatusPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.success,
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Дневной свет · ОК',
            style: AppTypography.caption.copyWith(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: AppColors.primaryAccent.withOpacity(0.4),
              width: 4,
            ),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: AppColors.roseDeep,
                      strokeWidth: 2.6,
                    ),
                  )
                : Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: AppColors.roseDeep,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
