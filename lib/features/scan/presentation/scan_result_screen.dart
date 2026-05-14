import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../../core/widgets/lina_avatar.dart';
import '../../../core/widgets/metric_ring.dart';
import '../../../core/widgets/pill.dart';
import '../../api/backend_api.dart';
import '../domain/scan_result.dart';

class ScanResultScreen extends ConsumerWidget {
  const ScanResultScreen({
    super.key,
    required this.scan,
    required this.onBack,
    required this.onAccept,
  });

  final ScanResult scan;
  final VoidCallback onBack;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                _Header(onBack: onBack, scan: scan),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, 110),
                    children: [
                      _Hero(scan: scan, photoUrl: api.scanPhotoUrl(scan.id)),
                      if (scan.hasQualityIssues) ...[
                        const SizedBox(height: AppSpacing.md),
                        _QualityBanner(messages: scan.qualityMessages.toList()),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      const EyebrowText('Метрики'),
                      const SizedBox(height: AppSpacing.sm),
                      _MetricsGrid(scan: scan),
                      const SizedBox(height: AppSpacing.lg),
                      const EyebrowText('Карта улучшений'),
                      const SizedBox(height: AppSpacing.sm),
                      _Heatmap(
                        scan: scan,
                        photoUrl: api.scanPhotoUrl(scan.id),
                        photoHeaders: api.imageAuthHeaders(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _LinaInsight(text: scan.insight),
                      if (scan.meta.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        _AnalysisMeta(meta: scan.meta),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.lg),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.roseDeep,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('В мой план ухода',
                              style: AppTypography.button),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 18),
                        ],
                      ),
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

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.scan});
  final VoidCallback onBack;
  final ScanResult scan;

  String _timeLabel() {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    final d = scan.createdAt.toLocal();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return 'Анализ · ${d.day} ${months[d.month]}, $hh:$mm';
  }

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
                EyebrowText(_timeLabel(), color: AppColors.roseDeep),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'Кожа сегодня — ',
                        style: AppTypography.h1.copyWith(fontSize: 26)),
                    TextSpan(
                      text: _scoreWord(scan.score),
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

  static String _scoreWord(int s) {
    if (s >= 85) return 'отлично';
    if (s >= 70) return 'хорошо';
    if (s >= 50) return 'нормально';
    return 'требует ухода';
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.scan, required this.photoUrl});
  final ScanResult scan;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: AppColors.primaryAccent.withOpacity(0.18)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, AppColors.primary],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const EyebrowText('Индекс кожи'),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${scan.score}',
                        style: AppTypography.display.copyWith(
                          fontSize: 56,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('/ 100',
                            style: AppTypography.caption),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Pill(
                    label: 'CV-анализ пикселей',
                    variant: PillVariant.outline,
                  ),
                ],
              ),
              const Spacer(),
              if (scan.hasPhoto)
                ClipOval(
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.primary,
                        child: const Icon(Icons.person_outline_rounded,
                            color: AppColors.roseDeep, size: 42),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                  child: const Icon(Icons.person_outline_rounded,
                      color: AppColors.roseDeep, size: 42),
                ),
            ],
          ),
        ),
        Positioned(
          right: -30,
          top: -30,
          child: IgnorePointer(
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryAccent.withOpacity(0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.scan});
  final ScanResult scan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: MetricRing(
              value: scan.hydration,
              label: 'Увлажнение',
              color: AppColors.info,
              size: 64,
              suffix: null,
            ),
          ),
          Expanded(
            child: MetricRing(
              value: scan.sebum,
              label: 'Себум',
              color: AppColors.gold,
              size: 64,
              suffix: null,
            ),
          ),
          Expanded(
            child: MetricRing(
              value: scan.tone,
              label: 'Тон',
              color: AppColors.primaryAccent,
              size: 64,
              suffix: null,
            ),
          ),
          Expanded(
            child: MetricRing(
              value: scan.pores,
              label: 'Поры',
              color: AppColors.roseDeep,
              size: 64,
              suffix: null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Heatmap extends ConsumerStatefulWidget {
  const _Heatmap({
    required this.scan,
    required this.photoUrl,
    required this.photoHeaders,
  });
  final ScanResult scan;
  final String photoUrl;
  final Map<String, String> photoHeaders;

  @override
  ConsumerState<_Heatmap> createState() => _HeatmapState();
}

class _HeatmapState extends ConsumerState<_Heatmap> {
  /// Face bbox we computed locally by running ML Kit on the saved photo.
  /// Wins over `widget.scan.face` when it's set — that one can be a stale
  /// skin-colour heuristic that covers the whole frame.
  FaceGeometry? _detected;

  /// True after we've attempted local detection (regardless of success).
  /// Avoids re-running detection on every rebuild.
  bool _detectAttempted = false;

  @override
  void initState() {
    super.initState();
    if (_serverFaceLooksGood(widget.scan.face)) {
      _detectAttempted = true;
    } else if (widget.scan.hasPhoto) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runDetect());
    } else {
      _detectAttempted = true;
    }
  }

  bool _serverFaceLooksGood(FaceGeometry? f) {
    if (f == null) return false;
    final w = f.x1 - f.x0, h = f.y1 - f.y0;
    // Reject obviously broken or 'whole frame' bboxes — those are the case
    // the user sees in the screenshot where the oval just sits dead-centre.
    if (w <= 0.1 || h <= 0.1) return false;
    if (w >= 0.85 || h >= 0.92) return false;
    return true;
  }

  Future<void> _runDetect() async {
    if (_detectAttempted) return;
    _detectAttempted = true;
    try {
      final bytes = await ref
          .read(backendApiProvider)
          .scanPhotoBytes(widget.scan.id);
      if (bytes == null || bytes.isEmpty || !mounted) return;
      final tmp =
          File('${Directory.systemTemp.path}/scan-${widget.scan.id}.jpg');
      await tmp.writeAsBytes(bytes, flush: true);
      final detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.15,
        ),
      );
      try {
        final input = InputImage.fromFilePath(tmp.path);
        final faces = await detector.processImage(input);
        if (faces.isEmpty || !mounted) return;
        faces.sort((a, b) =>
            (b.boundingBox.width * b.boundingBox.height)
                .compareTo(a.boundingBox.width * a.boundingBox.height));
        final box = faces.first.boundingBox;
        final size = await _decodeSize(Uint8List.fromList(bytes));
        if (size == null || !mounted) return;
        final w = size.width, h = size.height;
        if (w <= 0 || h <= 0) return;
        setState(() {
          _detected = FaceGeometry(bbox: [
            (box.left / w).clamp(0.0, 1.0),
            (box.top / h).clamp(0.0, 1.0),
            (box.right / w).clamp(0.0, 1.0),
            (box.bottom / h).clamp(0.0, 1.0),
          ]);
        });
      } finally {
        await detector.close();
        try {
          await tmp.delete();
        } catch (_) {/* ignore */}
      }
    } catch (e) {
      debugPrint('Result-screen face detect failed: $e');
    }
  }

  Future<({double width, double height})?> _decodeSize(
      Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final w = img.width.toDouble();
      final h = img.height.toDouble();
      img.dispose();
      return (width: w, height: h);
    } catch (_) {
      return null;
    }
  }

  FaceGeometry? get _effectiveFace =>
      _detected ?? widget.scan.face;

  @override
  Widget build(BuildContext context) {
    final zones = widget.scan.zones;
    final face = _effectiveFace;
    final scan = widget.scan;
    final photoUrl = widget.photoUrl;
    final photoHeaders = widget.photoHeaders;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        color: Colors.white,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (scan.hasPhoto)
                  Image.network(
                    photoUrl,
                    headers: photoHeaders,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _emptyBackdrop(),
                  )
                else
                  _emptyBackdrop(),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.0),
                        Colors.black.withOpacity(0.25),
                      ],
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _HeatmapPainter(zones: zones, face: face),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _zonePill('Лоб', zones.forehead),
                _zonePill('Т-зона', zones.tzone),
                _zonePill('Щёки', zones.cheeks),
                _zonePill('Подбородок', zones.chin),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBackdrop() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.blush, Colors.white],
          ),
        ),
      );

  Widget _zonePill(String label, int score) {
    final variant = score >= 75
        ? PillVariant.success
        : (score >= 60 ? PillVariant.soft : PillVariant.warning);
    return Pill(label: '$label · $score', variant: variant, dot: true);
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({required this.zones, required this.face});
  final ScanZones zones;
  final FaceGeometry? face;

  Color _colorFor(int score) {
    if (score >= 75) return AppColors.success;
    if (score >= 60) return AppColors.primaryAccent;
    return AppColors.warning;
  }

  void _drawBlob(
      Canvas canvas, Offset center, double rx, double ry, int score) {
    final color = _colorFor(score);
    final intensity = (1 - (score / 100)).clamp(0.25, 0.7);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(intensity), color.withOpacity(0)],
      ).createShader(Rect.fromCenter(
        center: center,
        width: rx * 2,
        height: ry * 2,
      ))
      ..blendMode = BlendMode.screen;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Determine where the face actually sits inside this widget. Falls back
    // to a centred oval covering most of the frame when we have no bbox.
    final Rect faceRect;
    final f = face;
    if (f != null) {
      faceRect = Rect.fromLTRB(
        f.x0 * size.width,
        f.y0 * size.height,
        f.x1 * size.width,
        f.y1 * size.height,
      );
    } else {
      faceRect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.5),
        width: size.width * 0.6,
        height: size.height * 0.75,
      );
    }

    // Soft oval outline around the detected face area.
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 1.2;
    final dashed = Path();
    final src = Path()..addOval(faceRect);
    for (final m in src.computeMetrics()) {
      var dist = 0.0;
      while (dist < m.length) {
        final next = math.min(dist + 5, m.length);
        dashed.addPath(m.extractPath(dist, next), Offset.zero);
        dist = next + 5;
      }
    }
    canvas.drawPath(dashed, outline);

    final fx = faceRect.left, fy = faceRect.top;
    final fw = faceRect.width, fh = faceRect.height;

    // Zones are placed proportionally inside the detected face bbox, so the
    // markers line up with the actual forehead / cheeks / chin of the user.
    Offset p(double rx, double ry) => Offset(fx + fw * rx, fy + fh * ry);

    _drawBlob(canvas, p(0.50, 0.15), fw * 0.34, fh * 0.10, zones.forehead);
    _drawBlob(canvas, p(0.50, 0.45), fw * 0.16, fh * 0.18, zones.tzone);
    _drawBlob(canvas, p(0.25, 0.55), fw * 0.18, fh * 0.12, zones.cheeks);
    _drawBlob(canvas, p(0.75, 0.55), fw * 0.18, fh * 0.12, zones.cheeks);
    _drawBlob(canvas, p(0.50, 0.86), fw * 0.22, fh * 0.10, zones.chin);

    // Subtle marker dots so it reads as 'analysed' even at low intensity.
    final dot = Paint()..color = Colors.white.withOpacity(0.85);
    for (final c in [
      p(0.50, 0.15),
      p(0.50, 0.45),
      p(0.25, 0.55),
      p(0.75, 0.55),
      p(0.50, 0.86),
    ]) {
      canvas.drawCircle(c, 2.4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.zones != zones || old.face != face;
}

class _QualityBanner extends StatelessWidget {
  const _QualityBanner({required this.messages});
  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 20, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Качество фото',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.warning),
                ),
                const SizedBox(height: 4),
                for (final m in messages) ...[
                  Text(
                    '• $m',
                    style: AppTypography.caption.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisMeta extends StatelessWidget {
  const _AnalysisMeta({required this.meta});
  final Map<String, dynamic> meta;

  @override
  Widget build(BuildContext context) {
    final size = meta['image_size'];
    final ms = meta['processing_ms'];
    final skin = meta['skin_pct'];
    final lum = meta['avg_lum'];
    final parts = <String>[
      if (size != null) '$size',
      if (skin != null) 'skin $skin%',
      if (lum != null) 'lum $lum',
      if (ms != null) '${ms}ms',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Center(
      child: Text(
        parts.join(' · '),
        style: AppTypography.eyebrow().copyWith(
          fontSize: 9,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _LinaInsight extends StatelessWidget {
  const _LinaInsight({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.roseDeep, AppColors.roseShadow],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinaAvatar(size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Лина · вывод',
                      style: AppTypography.eyebrow(
                        color: Colors.white.withOpacity(0.7),
                      ).copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '«$text»',
                      style: AppTypography.serifItalic(
                        fontSize: 17,
                        color: Colors.white,
                      ).copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: -40,
          top: -40,
          child: IgnorePointer(
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryAccent.withOpacity(0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
