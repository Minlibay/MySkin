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
import '../data/face_geom_builder.dart';
import '../domain/scan_result.dart';

class ScanResultScreen extends ConsumerWidget {
  const ScanResultScreen({
    super.key,
    required this.scan,
    required this.onBack,
    required this.onAccept,
    this.onOpenCatalog,
  });

  final ScanResult scan;
  final VoidCallback onBack;
  final VoidCallback onAccept;

  /// Called when the user taps "Подобрать средства" in a zone drill-down.
  /// Receives the catalog concern filter (e.g. 'acne', 'dehydration', or
  /// empty when no specific concern applies). Optional — when null the CTA
  /// is hidden.
  final void Function(String concern)? onOpenCatalog;

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
                        onOpenCatalog: onOpenCatalog,
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
    this.onOpenCatalog,
  });
  final ScanResult scan;
  final String photoUrl;
  final Map<String, String> photoHeaders;
  final void Function(String concern)? onOpenCatalog;

  @override
  ConsumerState<_Heatmap> createState() => _HeatmapState();
}

class _HeatmapState extends ConsumerState<_Heatmap>
    with SingleTickerProviderStateMixin {
  /// Face shape. Initialised synchronously from `widget.scan.face` when the
  /// scan upload included a valid face_geom; otherwise built async after a
  /// safety-net ML Kit pass on the result screen (covers older client
  /// builds and scans where on-device detection failed during capture).
  _FaceShape? _shape;

  /// Actual pixel size of the photo. Needed because the photo is rendered
  /// with BoxFit.cover into a 3:4 widget — when the original aspect differs,
  /// part of the image is cropped and bbox-space coordinates must be
  /// mapped through the same transform.
  double? _imgW;
  double? _imgH;

  /// True once we've decided whether a face exists — covers both the
  /// "scan.face was good" and "fallback ML Kit finished" cases. Until
  /// this flips, the build() method shows nothing (no fake oval, no
  /// "не распозналось" card — both would be lies while we're still
  /// trying).
  bool _detectionComplete = false;

  late final AnimationController _reveal;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    // Prefer scan-time face_geom: usually present and avoids a ~500ms
    // detection round-trip. When the payload only carries the bbox
    // (older client builds, fast-mode fallback) we still upgrade to a
    // full contour-aware shape on this screen if possible.
    final face = widget.scan.face;
    if (face?.contour != null && face?.landmarks != null) {
      _shape = _FaceShape.fromGeometry(face!);
      _detectionComplete = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reveal.forward(from: 0),
      );
    }

    if (widget.scan.hasPhoto) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runDetectionFlow());
    } else {
      _detectionComplete = true;
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  /// Fetches photo bytes, decodes their pixel size (needed for the cover
  /// transform), and — when we don't already have a rich shape — runs ML
  /// Kit locally as a safety net. Either path ends with [_detectionComplete]
  /// set to true and the appropriate UI (heatmap or _NoFaceOverlay).
  Future<void> _runDetectionFlow() async {
    try {
      final bytes = await ref
          .read(backendApiProvider)
          .scanPhotoBytes(widget.scan.id);
      if (bytes == null || bytes.isEmpty || !mounted) {
        if (mounted) setState(() => _detectionComplete = true);
        return;
      }
      final size = await _decodeSize(Uint8List.fromList(bytes));
      if (size != null && mounted) {
        setState(() {
          _imgW = size.width;
          _imgH = size.height;
        });
      }

      // If scan-time data was good (full contour + landmarks), nothing
      // more to do. We may still have a bbox-only shape from initState —
      // try to upgrade it to a richer one via local detection below.
      if (_shape != null && widget.scan.face?.contour != null) return;

      if (size == null) {
        // Can't run ML Kit without dimensions. Keep whatever shape we
        // managed to build from the bbox; otherwise reveal _NoFaceOverlay.
        if (mounted) {
          setState(() {
            _detectionComplete = true;
            if (_shape != null) _reveal.forward(from: 0);
          });
        }
        return;
      }

      final face = await _safetyNetDetect(bytes);
      if (!mounted) return;
      if (face != null) {
        final richGeom =
            buildFaceGeomJson(face, size.width, size.height);
        if (richGeom != null) {
          final geom = FaceGeometry.tryFromJson(richGeom);
          if (geom != null) {
            setState(() {
              _shape = _FaceShape.fromGeometry(geom);
              _detectionComplete = true;
            });
            _reveal.forward(from: 0);
            return;
          }
        }
      }

      // Detection failed locally AND scan-time. Fall back to whatever
      // bbox-only shape initState built; otherwise show the no-face card.
      setState(() {
        _detectionComplete = true;
        if (_shape == null && widget.scan.face != null) {
          _shape = _FaceShape.fromGeometry(widget.scan.face!);
        }
        if (_shape != null) _reveal.forward(from: 0);
      });
    } catch (e) {
      debugPrint('Result-screen detection flow failed: $e');
      if (mounted) setState(() => _detectionComplete = true);
    }
  }

  /// Three-pass ML Kit cascade on the saved photo. Mirrors the one in
  /// scan_screen so we have the same chance of finding a face that the
  /// upload flow had — useful when the scan itself was uploaded by an
  /// old client build that didn't run this cascade.
  Future<Face?> _safetyNetDetect(List<int> bytes) async {
    final tmp =
        File('${Directory.systemTemp.path}/scan-${widget.scan.id}.jpg');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      Face? face = await _tryDetect(
        tmp.path,
        accurate: true,
        contours: true,
        minFaceSize: 0.15,
      );
      face ??= await _tryDetect(
        tmp.path,
        accurate: true,
        contours: true,
        minFaceSize: 0.08,
      );
      face ??= await _tryDetect(
        tmp.path,
        accurate: false,
        contours: false,
        minFaceSize: 0.08,
      );
      return face;
    } finally {
      try {
        await tmp.delete();
      } catch (_) {/* ignore */}
    }
  }

  Future<Face?> _tryDetect(
    String path, {
    required bool accurate,
    required bool contours,
    required double minFaceSize,
  }) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode:
            accurate ? FaceDetectorMode.accurate : FaceDetectorMode.fast,
        enableContours: contours,
        enableLandmarks: contours,
        minFaceSize: minFaceSize,
      ),
    );
    try {
      final input = InputImage.fromFilePath(path);
      final faces = await detector.processImage(input);
      if (faces.isEmpty) return null;
      faces.sort((a, b) =>
          (b.boundingBox.width * b.boundingBox.height)
              .compareTo(a.boundingBox.width * a.boundingBox.height));
      return faces.first;
    } catch (e) {
      debugPrint('safety-net detect failed (accurate=$accurate): $e');
      return null;
    } finally {
      await detector.close();
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

  @override
  Widget build(BuildContext context) {
    final zones = widget.scan.zones;
    final shape = _shape;
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
                if (shape != null)
                  AnimatedBuilder(
                    animation: _reveal,
                    builder: (_, __) => CustomPaint(
                      painter: _HeatmapPainter(
                        zones: zones,
                        shape: shape,
                        progress:
                            Curves.easeOutCubic.transform(_reveal.value),
                        imageW: _imgW,
                        imageH: _imgH,
                      ),
                    ),
                  ),
                if (shape != null)
                  LayoutBuilder(
                    builder: (context, c) => _ZoneTapLayer(
                      shape: shape,
                      zones: zones,
                      size: c.biggest,
                      imageW: _imgW,
                      imageH: _imgH,
                      onTap: (key) => _showZoneSheet(context, key),
                    ),
                  ),
                if (shape == null &&
                    scan.hasPhoto &&
                    _detectionComplete)
                  // Honest empty-state — heatmap is hidden because ML Kit
                  // didn't find a face at scan time AND the safety-net
                  // detection on this screen also returned nothing.
                  const _NoFaceOverlay(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _zonePill(context, 'Лоб', zones.forehead, _ZoneKey.forehead),
                _zonePill(context, 'Т-зона', zones.tzone, _ZoneKey.tzone),
                _zonePill(context, 'Левая щека', zones.cheeks, _ZoneKey.leftCheek),
                _zonePill(context, 'Правая щека', zones.cheeks, _ZoneKey.rightCheek),
                _zonePill(context, 'Подбородок', zones.chin, _ZoneKey.chin),
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


  Widget _zonePill(
      BuildContext context, String label, int score, _ZoneKey key) {
    final variant = score >= 75
        ? PillVariant.success
        : (score >= 60 ? PillVariant.soft : PillVariant.warning);
    return InkWell(
      borderRadius: BorderRadius.circular(100),
      onTap: () => _showZoneSheet(context, key),
      child: Pill(label: '$label · $score', variant: variant, dot: true),
    );
  }

  void _showZoneSheet(BuildContext context, _ZoneKey key) {
    final zones = widget.scan.zones;
    final int score = switch (key) {
      _ZoneKey.forehead => zones.forehead,
      _ZoneKey.tzone => zones.tzone,
      _ZoneKey.leftCheek || _ZoneKey.rightCheek => zones.cheeks,
      _ZoneKey.chin => zones.chin,
    };
    final api = ref.read(backendApiProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ZoneSheet(
        zoneKey: key,
        score: score,
        insightFuture: api.fetchZoneInsight(widget.scan.id, _zoneApiKey(key)),
        onOpenCatalog: widget.onOpenCatalog,
      ),
    );
  }
}

String _zoneApiKey(_ZoneKey k) => switch (k) {
      _ZoneKey.forehead => 'forehead',
      _ZoneKey.tzone => 'tzone',
      _ZoneKey.leftCheek => 'left_cheek',
      _ZoneKey.rightCheek => 'right_cheek',
      _ZoneKey.chin => 'chin',
    };

/// Apply the Flutter `BoxFit.cover` transform to a normalised image-space
/// point so it lands on the matching pixel of a widget of size [size].
Offset _coverMap(Offset p, Size size, double? imgW, double? imgH) {
  double x = p.dx, y = p.dy;
  if (imgW != null && imgH != null && imgW > 0 && imgH > 0 && size.height > 0) {
    final imgA = imgW / imgH;
    final wA = size.width / size.height;
    if (imgA > wA) {
      final visW = wA / imgA;
      final off = (1 - visW) / 2;
      x = (p.dx - off) / visW;
    } else if (imgA < wA) {
      final visH = imgA / wA;
      final off = (1 - visH) / 2;
      y = (p.dy - off) / visH;
    }
  }
  return Offset(x * size.width, y * size.height);
}

/// Stable identifiers for the five zones the heatmap can drill into.
enum _ZoneKey { forehead, tzone, leftCheek, rightCheek, chin }

/// Result of ML Kit contour detection — face outline polygon + 5 zone
/// landmarks in normalised photo coordinates (0..1). When contour detection
/// fails we fall back to a synthesised ellipse from the plain bbox so the
/// overlay still renders, just less precise.
class _FaceShape {
  const _FaceShape({
    required this.contour,
    required this.forehead,
    required this.tzone,
    required this.leftCheek,
    required this.rightCheek,
    required this.chin,
  });

  final List<Offset> contour;
  final Offset forehead;
  final Offset tzone;
  final Offset leftCheek;
  final Offset rightCheek;
  final Offset chin;

  /// Build from the server-stored face_geom payload. Prefers the rich
  /// (contour + landmarks) path when those fields are present; falls back
  /// to the bbox-only ellipse layout when the client only managed to get
  /// a bbox.
  factory _FaceShape.fromGeometry(FaceGeometry f) {
    final contour = f.contour;
    final landmarks = f.landmarks;
    if (contour != null && landmarks != null) {
      Offset l(String key) =>
          Offset(landmarks[key]![0], landmarks[key]![1]);
      return _FaceShape(
        contour: contour.map((p) => Offset(p[0], p[1])).toList(growable: false),
        forehead: l('forehead'),
        tzone: l('tzone'),
        leftCheek: l('left_cheek'),
        rightCheek: l('right_cheek'),
        chin: l('chin'),
      );
    }
    return _FaceShape.fromBbox(f);
  }

  /// Last-resort fallback when contours weren't available — synthesises a
  /// 48-point ellipse and lays out 5 zone points by proportion.
  ///
  /// Crucially, we **tighten** the bbox here. The server's skin-colour
  /// heuristic often catches the face plus neck and shoulders, producing
  /// a bbox that's much taller than a real face (~1.8× width or more).
  /// Applied as-is, the proportional layout (cheeks at 0.55 of bbox
  /// height) then drops cheek markers onto the user's chest.
  ///
  /// Real human faces are roughly width:height ≈ 1:1.3. If we got a
  /// taller bbox, we anchor at the top (face is in the upper portion of
  /// a head+shoulders shot) and trim the bottom down to that ratio.
  factory _FaceShape.fromBbox(FaceGeometry f) {
    double x0 = f.x0, y0 = f.y0, x1 = f.x1, y1 = f.y1;
    final origW = x1 - x0;
    final origH = y1 - y0;
    const idealHToW = 1.3;
    if (origW > 0 && origH > origW * (idealHToW + 0.15)) {
      // Anchor face top at bbox top — torso/neck went below the face in
      // the skin-colour heuristic, so trimming from below recovers the
      // actual face area.
      y1 = y0 + origW * idealHToW;
    }

    final cx = (x0 + x1) / 2;
    final cy = (y0 + y1) / 2;
    final rx = (x1 - x0) / 2;
    final ry = (y1 - y0) / 2;
    const steps = 48;
    final contour = <Offset>[
      for (var i = 0; i < steps; i++)
        Offset(
          cx + math.cos(i / steps * 2 * math.pi) * rx,
          cy + math.sin(i / steps * 2 * math.pi) * ry,
        ),
    ];
    return _FaceShape(
      contour: contour,
      forehead: Offset(cx, y0 + (y1 - y0) * 0.15),
      tzone: Offset(cx, y0 + (y1 - y0) * 0.45),
      leftCheek: Offset(x0 + (x1 - x0) * 0.25, y0 + (y1 - y0) * 0.55),
      rightCheek: Offset(x0 + (x1 - x0) * 0.75, y0 + (y1 - y0) * 0.55),
      chin: Offset(cx, y0 + (y1 - y0) * 0.86),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.zones,
    required this.shape,
    required this.progress,
    this.imageW,
    this.imageH,
  });
  final ScanZones zones;
  final _FaceShape shape;
  final double progress; // 0..1 reveal timeline
  final double? imageW;
  final double? imageH;

  Color _colorFor(int score) {
    if (score >= 75) return AppColors.success;
    if (score >= 60) return AppColors.primaryAccent;
    return AppColors.warning;
  }

  Offset _map(Offset p, Size size) => _coverMap(p, size, imageW, imageH);

  /// Reveal sub-timing helper — returns the local 0..1 progress for a
  /// sub-animation that starts at `start` and lasts `length` on the global
  /// timeline.
  double _sub(double start, double length) =>
      ((progress - start) / length).clamp(0.0, 1.0);

  void _blob(Canvas canvas, Offset center, double rx, double ry,
      int score, double opacity) {
    if (opacity <= 0) return;
    final color = _colorFor(score);
    final intensity = (1 - score / 100).clamp(0.25, 0.7) * opacity;
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
    if (shape.contour.length < 3) return;
    final pts = shape.contour
        .map((p) => _map(p, size))
        .toList(growable: false);

    // 1. Trace the face outline along the actual contour — first 35% of
    // the reveal timeline. Dashed for the diagnostic-instrument look.
    final outlineP = _sub(0.0, 0.35);
    if (outlineP > 0) {
      final full = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        full.lineTo(pts[i].dx, pts[i].dy);
      }
      full.close();
      final dashed = Path();
      for (final m in full.computeMetrics()) {
        final endLen = m.length * outlineP;
        var dist = 0.0;
        while (dist < endLen) {
          final next = math.min(dist + 5.0, endLen);
          dashed.addPath(m.extractPath(dist, next), Offset.zero);
          dist = next + 5.0;
        }
      }
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withOpacity(0.65)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(dashed, outline);
    }

    // Approximate face extents in widget pixels so blob sizes scale with
    // however big the face actually is on screen.
    final xs = pts.map((p) => p.dx);
    final ys = pts.map((p) => p.dy);
    final fw = xs.reduce(math.max) - xs.reduce(math.min);
    final fh = ys.reduce(math.max) - ys.reduce(math.min);

    // 2. Staggered blob reveal — each zone gets a 250ms ramp.
    final blobs = <(Offset, double, double, int, double)>[
      (_map(shape.forehead, size), fw * 0.36, fh * 0.10, zones.forehead, 0.38),
      (_map(shape.tzone, size), fw * 0.18, fh * 0.18, zones.tzone, 0.46),
      (_map(shape.leftCheek, size), fw * 0.18, fh * 0.13, zones.cheeks, 0.54),
      (_map(shape.rightCheek, size), fw * 0.18, fh * 0.13, zones.cheeks, 0.54),
      (_map(shape.chin, size), fw * 0.22, fh * 0.10, zones.chin, 0.62),
    ];
    for (final b in blobs) {
      _blob(canvas, b.$1, b.$2, b.$3, b.$4, _sub(b.$5, 0.25));
    }

    // 3. Marker dots fade-in near the end — feels like the diagnostic
    // "pins" landing on the result.
    final dotsP = _sub(0.65, 0.25);
    if (dotsP > 0) {
      final dot = Paint()..color = Colors.white.withOpacity(0.85 * dotsP);
      for (final c in [
        shape.forehead,
        shape.tzone,
        shape.leftCheek,
        shape.rightCheek,
        shape.chin,
      ]) {
        canvas.drawCircle(_map(c, size), 2.4 * dotsP, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.zones != zones ||
      old.shape != shape ||
      old.progress != progress ||
      old.imageW != imageW ||
      old.imageH != imageH;
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

/// Transparent hit-targets sitting on top of the heatmap blobs so the user
/// can tap a zone to drill into it. Each target is 44pt (Apple HIG minimum).
class _ZoneTapLayer extends StatelessWidget {
  const _ZoneTapLayer({
    required this.shape,
    required this.zones,
    required this.size,
    required this.onTap,
    this.imageW,
    this.imageH,
  });

  final _FaceShape shape;
  final ScanZones zones;
  final Size size;
  final void Function(_ZoneKey) onTap;
  final double? imageW;
  final double? imageH;

  @override
  Widget build(BuildContext context) {
    Offset pos(Offset p) => _coverMap(p, size, imageW, imageH);
    final targets = <(_ZoneKey, Offset)>[
      (_ZoneKey.forehead, pos(shape.forehead)),
      (_ZoneKey.tzone, pos(shape.tzone)),
      (_ZoneKey.leftCheek, pos(shape.leftCheek)),
      (_ZoneKey.rightCheek, pos(shape.rightCheek)),
      (_ZoneKey.chin, pos(shape.chin)),
    ];
    const r = 28.0;
    return Stack(
      children: [
        for (final t in targets)
          Positioned(
            left: t.$2.dx - r,
            top: t.$2.dy - r,
            width: r * 2,
            height: r * 2,
            child: Semantics(
              button: true,
              label: _zoneLabel(t.$1),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onTap(t.$1),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _zoneLabel(_ZoneKey key) => switch (key) {
      _ZoneKey.forehead => 'Лоб',
      _ZoneKey.tzone => 'Т-зона',
      _ZoneKey.leftCheek => 'Левая щека',
      _ZoneKey.rightCheek => 'Правая щека',
      _ZoneKey.chin => 'Подбородок',
    };

class _ZoneSheet extends StatefulWidget {
  const _ZoneSheet({
    required this.zoneKey,
    required this.score,
    required this.insightFuture,
    this.onOpenCatalog,
  });

  final _ZoneKey zoneKey;
  final int score;
  final Future<ZoneInsight> insightFuture;
  final void Function(String concern)? onOpenCatalog;

  @override
  State<_ZoneSheet> createState() => _ZoneSheetState();
}

class _ZoneSheetState extends State<_ZoneSheet> {
  late final Future<ZoneInsight> _future = widget.insightFuture;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(widget.score);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FutureBuilder<ZoneInsight>(
          future: _future,
          builder: (_, snap) {
            final loading = snap.connectionState != ConnectionState.done;
            // Fall back to the static table if the server call failed.
            final data = snap.hasData
                ? snap.data!
                : (loading
                    ? null
                    : _fallbackInsight(widget.zoneKey, widget.score));

            return ListView(
              controller: controller,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EyebrowText(status.eyebrow, color: status.color),
                          const SizedBox(height: 6),
                          Text(_zoneLabel(widget.zoneKey),
                              style:
                                  AppTypography.h1.copyWith(fontSize: 28)),
                        ],
                      ),
                    ),
                    Text(
                      '${widget.score}',
                      style: AppTypography.display.copyWith(
                        fontSize: 44,
                        height: 1,
                        color: status.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (data == null) ...[
                  _ZoneBlockSkeleton(lines: 2),
                  const SizedBox(height: 12),
                  _ZoneBlockSkeleton(lines: 3),
                ] else ...[
                  _ZoneBlock(title: 'Что замечаем', body: data.issue),
                  const SizedBox(height: 12),
                  _ZoneBlock(title: 'Что поможет', bullets: data.remedies),
                ],
                const SizedBox(height: 20),
                if (data != null &&
                    widget.onOpenCatalog != null &&
                    data.concern.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        widget.onOpenCatalog!(data.concern);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.roseDeep,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Подобрать средства',
                              style: AppTypography.button),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                if (data != null &&
                    widget.onOpenCatalog != null &&
                    data.concern.isNotEmpty)
                  const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Закрыть'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ZoneBlockSkeleton extends StatelessWidget {
  const _ZoneBlockSkeleton({required this.lines});
  final int lines;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < lines; i++) ...[
            Container(
              width: double.infinity,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            if (i < lines - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Last-resort copy if the server call fails — same wording as the backend's
/// own fallback, so the UX is identical in both branches.
ZoneInsight _fallbackInsight(_ZoneKey k, int score) {
  final info = _zoneInsight(k, score);
  return ZoneInsight(
    zone: _zoneApiKey(k),
    score: score,
    issue: info.issue,
    remedies: info.remedies,
    concern: _fallbackConcern(k, score),
  );
}

String _fallbackConcern(_ZoneKey k, int score) {
  final low = score < 55;
  final mid = score >= 55 && score < 70;
  if (!low && !mid) return ''; // High score → no CTA.
  return switch (k) {
    _ZoneKey.forehead => 'dehydration',
    _ZoneKey.tzone => 'acne',
    _ZoneKey.leftCheek || _ZoneKey.rightCheek => 'redness',
    _ZoneKey.chin => 'acne',
  };
}

class _ZoneBlock extends StatelessWidget {
  const _ZoneBlock({required this.title, this.body, this.bullets});
  final String title;
  final String? body;
  final List<String>? bullets;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EyebrowText(title),
          const SizedBox(height: 8),
          if (body != null) Text(body!, style: AppTypography.bodyMedium),
          if (bullets != null)
            for (final b in bullets!)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 10),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(b, style: AppTypography.bodyMedium),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

({String eyebrow, Color color}) _statusFor(int score) {
  if (score >= 85) return (eyebrow: 'Отлично', color: AppColors.success);
  if (score >= 70) return (eyebrow: 'Хорошо', color: AppColors.success);
  if (score >= 55) return (eyebrow: 'Норма', color: AppColors.primaryAccent);
  return (eyebrow: 'Нужно внимание', color: AppColors.warning);
}

/// Static rule-table for per-zone diagnostics. Conservative wording — this
/// is product copy, not medical advice. Later we can swap this for a
/// GigaChat call keyed on (zone, score, scan).
({String issue, List<String> remedies}) _zoneInsight(_ZoneKey k, int score) {
  final low = score < 55;
  final mid = score >= 55 && score < 70;
  switch (k) {
    case _ZoneKey.forehead:
      if (low) {
        return (
          issue:
              'На лбу заметна обезвоженность и неровный тон. Часто это след '
                  'стресса, обогревателя или слишком плотного крема.',
          remedies: [
            'Гиалуроновая кислота утром, под крем',
            'Лёгкий пантенол на ночь',
            'Перерыв в кислотах на 2–3 дня',
          ],
        );
      }
      if (mid) {
        return (
          issue:
              'Лоб в стабильной форме, но запас увлажнения небольшой — кожа '
                  'может тянуть к вечеру.',
          remedies: [
            'Сыворотка с ниацинамидом 5%',
            'Питательный ночной крем 2–3 раза в неделю',
          ],
        );
      }
      return (
        issue: 'Лоб в отличной форме. Поддерживаем баланс — ничего нового.',
        remedies: [
          'SPF 50 каждое утро',
          'Раз в неделю — лёгкий пилинг с PHA',
        ],
      );
    case _ZoneKey.tzone:
      if (low) {
        return (
          issue:
              'Т-зона активная: повышенный себум, расширенные поры и риск '
                  'воспалений. Скорее всего из-за плотных текстур и сладкого.',
          remedies: [
            'Салициловая кислота 2% точечно вечером',
            'Цинк или ниацинамид 10% утром',
            'Матирующий тонер вместо плотного крема',
          ],
        );
      }
      if (mid) {
        return (
          issue:
              'Т-зона работает нормально, но к вечеру появляется блеск и '
                  'выделяются поры.',
          remedies: [
            'Ниацинамид 5–10% утром',
            'Глиняная маска 1 раз в неделю',
          ],
        );
      }
      return (
        issue: 'Т-зона сбалансирована — это редкий и хороший случай.',
        remedies: [
          'Лёгкая текстура крема, чтобы не утяжелять',
          'BHA 1 раз в неделю как профилактика',
        ],
      );
    case _ZoneKey.leftCheek:
    case _ZoneKey.rightCheek:
      if (low) {
        return (
          issue:
              'На щеках видны сухость, реактивная краснота или следы. '
                  'Часто это барьер просит восстановления, а не активов.',
          remedies: [
            'Церамиды и сквалан вечером',
            'Пантенол утром под SPF',
            'Пауза в ретиноле и кислотах на неделю',
          ],
        );
      }
      if (mid) {
        return (
          issue:
              'Щёки в норме, но кожа реагирует на холод и плотный макияж. '
                  'Барьер чуть тоньше, чем хотелось бы.',
          remedies: [
            'Крем с центеллой утром',
            'Лёгкая эмульсия с церамидами на ночь',
          ],
        );
      }
      return (
        issue: 'Щёки сияют — увлажнение и барьер в порядке.',
        remedies: [
          'SPF 50 каждое утро',
          'Сыворотка с витамином C для тона',
        ],
      );
    case _ZoneKey.chin:
      if (low) {
        return (
          issue:
              'Подбородок реагирует на гормоны и стресс — там чаще всего '
                  'появляются воспаления и плотные комедоны.',
          remedies: [
            'Азелаиновая кислота 10% точечно вечером',
            'BHA-тонер 2–3 раза в неделю',
            'Не трогать руками в течение дня',
          ],
        );
      }
      if (mid) {
        return (
          issue:
              'Подбородок стабилен, но иногда выскакивают единичные '
                  'воспаления — обычно в дни недосыпа.',
          remedies: [
            'Точечный гель с цинком',
            'Лёгкое увлажнение, без масел',
          ],
        );
      }
      return (
        issue: 'Подбородок в норме — продолжаем ухаживать как сейчас.',
        remedies: [
          'Поддерживающий крем без отдушек',
          'SPF 50 каждое утро',
        ],
      );
  }
}

/// Shown over the photo when ML Kit couldn't find a face at scan time.
/// We don't draw a fake heatmap — instead we say so honestly and invite
/// the user to retake. The photo and metrics still display below.
class _NoFaceOverlay extends StatelessWidget {
  const _NoFaceOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.45),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.face_retouching_off_outlined,
                  color: AppColors.roseDeep, size: 28),
              const SizedBox(height: 10),
              Text(
                'Лицо не распозналось',
                style: AppTypography.h2.copyWith(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Карта улучшений работает, когда видно всё лицо. '
                'Метрики по пикселям мы рассчитали — переснимите при '
                'дневном свете, чтобы увидеть карту.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
