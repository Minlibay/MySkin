import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../api/backend_api.dart';
import '../domain/scan_result.dart';

enum _LightLevel { tooDark, ok, tooBright, unknown }

extension on _LightLevel {
  String get label {
    switch (this) {
      case _LightLevel.tooDark:
        return 'Темновато';
      case _LightLevel.ok:
        return 'Дневной свет · ОК';
      case _LightLevel.tooBright:
        return 'Слишком ярко';
      case _LightLevel.unknown:
        return 'Свет: проверяю…';
    }
  }

  Color get color {
    switch (this) {
      case _LightLevel.ok:
        return AppColors.success;
      case _LightLevel.tooDark:
      case _LightLevel.tooBright:
        return AppColors.warning;
      case _LightLevel.unknown:
        return Colors.white.withOpacity(0.6);
    }
  }
}

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _busy = false;
  String? _error;
  late final AnimationController _pulse;

  CameraController? _camera;
  CameraDescription? _cameraDesc;
  Future<void>? _initFuture;
  String? _cameraError;

  late final FaceDetector _faceDetector;
  bool _processing = false;
  int _frameSkip = 0;
  bool _streaming = false;

  _LightLevel _light = _LightLevel.unknown;
  // EMA of average luminance to avoid flicker.
  double _lumaEma = -1;

  _DetectedFace? _face;
  DateTime _faceSeenAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.25,
      ),
    );
    _initFuture = _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _stopStream();
    _camera?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopStream();
      cam.dispose();
      _camera = null;
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _initFuture = _initCamera();
      if (mounted) setState(() {});
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _cameraError = 'Камера недоступна на этом устройстве');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _camera = ctrl;
        _cameraDesc = front;
        _cameraError = null;
      });
      await _startStream();
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = e.code == 'CameraAccessDenied'
            ? 'Нет доступа к камере. Разреши в настройках.'
            : 'Камера: ${e.description ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = 'Камера: $e');
    }
  }

  Future<void> _startStream() async {
    final cam = _camera;
    if (cam == null || _streaming) return;
    try {
      await cam.startImageStream(_onFrame);
      _streaming = true;
    } catch (e) {
      // Image streaming might not be supported (e.g. emulator). Silent fallback.
      debugPrint('startImageStream failed: $e');
    }
  }

  Future<void> _stopStream() async {
    final cam = _camera;
    if (cam == null || !_streaming) return;
    try {
      await cam.stopImageStream();
    } catch (_) {}
    _streaming = false;
  }

  void _onFrame(CameraImage image) {
    if (_processing) return;
    // Process roughly every 3rd frame to keep CPU low.
    _frameSkip = (_frameSkip + 1) % 3;
    if (_frameSkip != 0) return;
    _processing = true;
    _analyzeFrame(image).whenComplete(() => _processing = false);
  }

  Future<void> _analyzeFrame(CameraImage image) async {
    _updateLight(image);
    await _detectFace(image);
  }

  void _updateLight(CameraImage image) {
    if (image.planes.isEmpty) return;
    double avg;
    if (Platform.isAndroid) {
      // NV21: first plane is Y (luminance, 0..255).
      final y = image.planes.first.bytes;
      avg = _sampleAverage(y, step: 137);
    } else {
      // BGRA8888 single plane — average of B,G,R.
      final px = image.planes.first.bytes;
      avg = _sampleAverageBgra(px, step: 41);
    }
    // Smooth with EMA so flicker doesn't toggle the pill rapidly.
    _lumaEma = _lumaEma < 0 ? avg : (_lumaEma * 0.7 + avg * 0.3);
    final level = _lumaEma < 55
        ? _LightLevel.tooDark
        : _lumaEma > 215
            ? _LightLevel.tooBright
            : _LightLevel.ok;
    if (level != _light && mounted) {
      setState(() => _light = level);
    }
  }

  double _sampleAverage(Uint8List bytes, {required int step}) {
    if (bytes.isEmpty) return 0;
    var sum = 0;
    var n = 0;
    for (var i = 0; i < bytes.length; i += step) {
      sum += bytes[i];
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  double _sampleAverageBgra(Uint8List bytes, {required int step}) {
    if (bytes.length < 4) return 0;
    final stride = 4 * step;
    var sum = 0;
    var n = 0;
    for (var i = 0; i + 2 < bytes.length; i += stride) {
      // luminance approximation: 0.114*B + 0.587*G + 0.299*R
      sum += (0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2])
          .round();
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  Future<void> _detectFace(CameraImage image) async {
    final desc = _cameraDesc;
    if (desc == null) return;
    final input = _toInputImage(image, desc);
    if (input == null) return;
    try {
      final faces = await _faceDetector.processImage(input);
      if (!mounted) return;
      if (faces.isEmpty) {
        // Hold the last face for a short window to avoid flicker between frames.
        if (DateTime.now().difference(_faceSeenAt) >
            const Duration(milliseconds: 600)) {
          if (_face != null) setState(() => _face = null);
        }
        return;
      }
      // Pick the largest face (closest to camera).
      faces.sort((a, b) =>
          (b.boundingBox.width * b.boundingBox.height)
              .compareTo(a.boundingBox.width * a.boundingBox.height));
      final f = faces.first;
      final rotated = _rotatedImageSize(image, desc);
      final detected = _DetectedFace(
        bounds: f.boundingBox,
        imageSize: rotated,
        mirror: desc.lensDirection == CameraLensDirection.front,
        leftEye: f.landmarks[FaceLandmarkType.leftEye]?.position,
        rightEye: f.landmarks[FaceLandmarkType.rightEye]?.position,
        noseBase: f.landmarks[FaceLandmarkType.noseBase]?.position,
        mouthLeft: f.landmarks[FaceLandmarkType.leftMouth]?.position,
        mouthRight: f.landmarks[FaceLandmarkType.rightMouth]?.position,
        mouthBottom: f.landmarks[FaceLandmarkType.bottomMouth]?.position,
        leftCheek: f.landmarks[FaceLandmarkType.leftCheek]?.position,
        rightCheek: f.landmarks[FaceLandmarkType.rightCheek]?.position,
        faceContour: f.contours[FaceContourType.face]?.points,
        leftEyeContour: f.contours[FaceContourType.leftEye]?.points,
        rightEyeContour: f.contours[FaceContourType.rightEye]?.points,
        upperLipTop: f.contours[FaceContourType.upperLipTop]?.points,
        lowerLipBottom: f.contours[FaceContourType.lowerLipBottom]?.points,
        noseBridge: f.contours[FaceContourType.noseBridge]?.points,
      );
      _faceSeenAt = DateTime.now();
      setState(() => _face = detected);
    } catch (e) {
      debugPrint('Face detect error: $e');
    }
  }

  Size _rotatedImageSize(CameraImage image, CameraDescription desc) {
    final rot = desc.sensorOrientation;
    if (rot == 90 || rot == 270) {
      return Size(image.height.toDouble(), image.width.toDouble());
    }
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  InputImage? _toInputImage(CameraImage image, CameraDescription desc) {
    final rotation =
        InputImageRotationValue.fromRawValue(desc.sensorOrientation) ??
            InputImageRotation.rotation0deg;
    final format =
        InputImageFormatValue.fromRawValue(image.format.raw) ?? (Platform.isAndroid
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888);
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  String _hint() {
    if (_cameraError != null) return 'Камера недоступна';
    if (_light == _LightLevel.tooDark) {
      return 'Темновато — найди свет поярче';
    }
    if (_light == _LightLevel.tooBright) {
      return 'Слишком ярко — отойди от окна';
    }
    final f = _face;
    if (f == null) return 'Совмести овал лица с маркерами';
    final fillRatio = (f.bounds.width * f.bounds.height) /
        (f.imageSize.width * f.imageSize.height);
    if (fillRatio < 0.07) return 'Чуть ближе';
    if (fillRatio > 0.35) return 'Чуть дальше';
    return 'Отлично — держи ровно';
  }

  String _headline() {
    final f = _face;
    if (_cameraError != null) return 'Не вижу камеру';
    if (_light == _LightLevel.tooDark) {
      return 'Нужно больше света —\nподойди к окну';
    }
    if (f == null) return 'Покажи лицо в кадр —\nи держи ровно';
    return 'Чуть выше подбородок —\nи держи ровно';
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) {
      return _pickFromGallery();
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _stopStream();
      final pic = await cam.takePicture();
      final bytes = await File(pic.path).readAsBytes();
      await _uploadAndFinish(bytes, mime: 'image/jpeg');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не получилось снять: $e';
      });
      await _startStream();
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1600,
      );
      if (picked == null) {
        if (!mounted) return;
        setState(() => _busy = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      await _uploadAndFinish(bytes, mime: picked.mimeType ?? 'image/jpeg');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не получилось загрузить: $e';
      });
    }
  }

  Future<void> _uploadAndFinish(List<int> bytes,
      {required String mime}) async {
    final b64 = base64Encode(bytes);
    final result = await ref.read(backendApiProvider).uploadScan(
          photoBase64: b64,
          mime: mime,
        );
    if (!mounted) return;
    widget.onResult(result);
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    final previewAspect = cam?.value.aspectRatio ?? (16 / 9);
    return Scaffold(
      backgroundColor: const Color(0xFF0F0A0C),
      body: Stack(
        children: [
          Positioned.fill(
            child: _CameraBackdrop(
              controller: _camera,
              initFuture: _initFuture,
              errorText: _cameraError,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 1.1,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.35),
                      Colors.black.withOpacity(0.75),
                    ],
                    stops: const [0.35, 0.7, 1],
                  ),
                ),
              ),
            ),
          ),
          // Adaptive face mask overlay
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => CustomPaint(
                  painter: _FaceMeshPainter(
                    t: _pulse.value,
                    face: _face,
                    previewAspect: previewAspect,
                    locked: _light == _LightLevel.ok && _face != null,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        _GlassButton(
                          icon: Icons.close_rounded,
                          onTap: widget.onBack,
                        ),
                        const Spacer(),
                        _LightStatusPill(level: _light),
                        const Spacer(),
                        _GlassButton(
                          icon: Icons.photo_library_rounded,
                          onTap: _busy ? () {} : _pickFromGallery,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Text(
                          _headline(),
                          textAlign: TextAlign.center,
                          style: AppTypography.serifItalic(
                            fontSize: 26,
                            color: Colors.white,
                          ).copyWith(height: 1.15),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hint(),
                          textAlign: TextAlign.center,
                          style: AppTypography.caption.copyWith(
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
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
                                      _cameraError ??
                                      '12 параметров · фото не покидает наш сервер',
                                  style: AppTypography.caption.copyWith(
                                    color: (_error != null ||
                                            _cameraError != null)
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

class _CameraBackdrop extends StatelessWidget {
  const _CameraBackdrop({
    required this.controller,
    required this.initFuture,
    required this.errorText,
  });

  final CameraController? controller;
  final Future<void>? initFuture;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    if (errorText != null) {
      return Container(
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
      );
    }
    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snap) {
        final c = controller;
        if (c == null || !c.value.isInitialized) {
          return Container(color: const Color(0xFF1A1116));
        }
        final size = MediaQuery.of(context).size;
        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.width,
                height: size.width * c.value.aspectRatio,
                child: CameraPreview(c),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Snapshot of the latest detected face, in image-coordinates (already
/// rotated to upright by ML Kit). The painter projects these onto the
/// canvas using [_previewRect].
class _DetectedFace {
  _DetectedFace({
    required this.bounds,
    required this.imageSize,
    required this.mirror,
    this.leftEye,
    this.rightEye,
    this.noseBase,
    this.mouthLeft,
    this.mouthRight,
    this.mouthBottom,
    this.leftCheek,
    this.rightCheek,
    this.faceContour,
    this.leftEyeContour,
    this.rightEyeContour,
    this.upperLipTop,
    this.lowerLipBottom,
    this.noseBridge,
  });

  final Rect bounds;
  final Size imageSize;
  final bool mirror;
  final math.Point<int>? leftEye;
  final math.Point<int>? rightEye;
  final math.Point<int>? noseBase;
  final math.Point<int>? mouthLeft;
  final math.Point<int>? mouthRight;
  final math.Point<int>? mouthBottom;
  final math.Point<int>? leftCheek;
  final math.Point<int>? rightCheek;
  final List<math.Point<int>>? faceContour;
  final List<math.Point<int>>? leftEyeContour;
  final List<math.Point<int>>? rightEyeContour;
  final List<math.Point<int>>? upperLipTop;
  final List<math.Point<int>>? lowerLipBottom;
  final List<math.Point<int>>? noseBridge;
}

class _FaceMeshPainter extends CustomPainter {
  _FaceMeshPainter({
    required this.t,
    required this.face,
    required this.previewAspect,
    required this.locked,
  });

  final double t;
  final _DetectedFace? face;
  final double previewAspect;
  final bool locked;

  /// On-screen rect occupied by the camera preview, matching the layout in
  /// [_CameraBackdrop]: width = screen, height = screen * aspectRatio,
  /// vertically centred, overflow clipped.
  Rect _previewRect(Size canvas) {
    final h = canvas.width * previewAspect;
    final top = (canvas.height - h) / 2;
    return Rect.fromLTWH(0, top, canvas.width, h);
  }

  Offset _map(num x, num y, Size imgSize, bool mirror, Rect rect) {
    double mx = x.toDouble();
    if (mirror) mx = imgSize.width - mx;
    final sx = rect.width / imgSize.width;
    final sy = rect.height / imgSize.height;
    return Offset(rect.left + mx * sx, rect.top + y.toDouble() * sy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final f = face;
    if (f == null) {
      _paintPlaceholder(canvas, size);
      return;
    }
    final rect = _previewRect(size);

    Offset mp(num x, num y) => _map(x, y, f.imageSize, f.mirror, rect);
    Offset mPoint(math.Point<int> p) => mp(p.x, p.y);

    // Face oval — derived from bounding box, slightly inflated.
    final left = f.mirror ? f.imageSize.width - f.bounds.right : f.bounds.left;
    final centerImg =
        Offset(left + f.bounds.width / 2, f.bounds.top + f.bounds.height / 2);
    final center = Offset(
      rect.left + centerImg.dx * (rect.width / f.imageSize.width),
      rect.top + centerImg.dy * (rect.height / f.imageSize.height),
    );
    final wScale = rect.width / f.imageSize.width;
    final hScale = rect.height / f.imageSize.height;
    final ovalRect = Rect.fromCenter(
      center: center,
      width: f.bounds.width * wScale * 1.08,
      height: f.bounds.height * hScale * 1.18,
    );

    final accent = locked
        ? AppColors.success
        : AppColors.primaryAccent;

    // 1) Face contour from ML Kit (preferred) — falls back to dashed oval.
    final contour = f.faceContour;
    if (contour != null && contour.length > 6) {
      final path = Path();
      for (var i = 0; i < contour.length; i++) {
        final pt = mPoint(contour[i]);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(
        _dashed(path, dash: 5, gap: 4),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent.withOpacity(0.75)
          ..strokeWidth = 1.2,
      );
    } else {
      final dashed = Path();
      _addDashedOval(dashed, ovalRect, dashWidth: 4, dashSpace: 5);
      canvas.drawPath(
        dashed,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent.withOpacity(0.75)
          ..strokeWidth = 1.2,
      );
    }

    // 2) Mesh — curved guides aligned to detected landmarks.
    final mesh = Paint()
      ..style = PaintingStyle.stroke
      ..color = accent.withOpacity(0.35)
      ..strokeWidth = 0.7;
    final lEye = f.leftEye, rEye = f.rightEye;
    if (lEye != null && rEye != null) {
      final l = mPoint(lEye);
      final r = mPoint(rEye);
      final brow = Path()
        ..moveTo(l.dx - 18, l.dy - 22)
        ..quadraticBezierTo(
          (l.dx + r.dx) / 2,
          ((l.dy + r.dy) / 2) - 40,
          r.dx + 18,
          r.dy - 22,
        );
      canvas.drawPath(brow, mesh);
      final eyeLine = Path()
        ..moveTo(l.dx - 24, l.dy)
        ..quadraticBezierTo(
          (l.dx + r.dx) / 2,
          ((l.dy + r.dy) / 2) - 6,
          r.dx + 24,
          r.dy,
        );
      canvas.drawPath(eyeLine, mesh);
    }
    final ml = f.mouthLeft, mr = f.mouthRight, mb = f.mouthBottom;
    if (ml != null && mr != null) {
      final l = mPoint(ml);
      final r = mPoint(mr);
      final lipLine = Path()
        ..moveTo(l.dx - 14, l.dy)
        ..quadraticBezierTo(
          (l.dx + r.dx) / 2,
          mb != null ? mPoint(mb).dy : ((l.dy + r.dy) / 2 + 6),
          r.dx + 14,
          r.dy,
        );
      canvas.drawPath(lipLine, mesh);
    }
    // Vertical guides (nose bridge + side temples)
    final nb = f.noseBridge;
    if (nb != null && nb.length > 1) {
      final path = Path();
      for (var i = 0; i < nb.length; i++) {
        final pt = mPoint(nb[i]);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, mesh);
    }

    // 3) Eye outlines from contour points.
    void drawEye(List<math.Point<int>>? pts) {
      if (pts == null || pts.length < 4) return;
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final p = mPoint(pts[i]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent.withOpacity(0.85)
          ..strokeWidth = 1.0,
      );
    }

    drawEye(f.leftEyeContour);
    drawEye(f.rightEyeContour);

    // 4) Mouth outline (upper + lower lip)
    void drawLip(List<math.Point<int>>? pts) {
      if (pts == null || pts.length < 2) return;
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final p = mPoint(pts[i]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent.withOpacity(0.85)
          ..strokeWidth = 1.0,
      );
    }

    drawLip(f.upperLipTop);
    drawLip(f.lowerLipBottom);

    // 5) Landmark anchors
    final anchorPaint = Paint()..color = accent;
    final anchors = <Offset>[
      if (f.leftEye != null) mPoint(f.leftEye!),
      if (f.rightEye != null) mPoint(f.rightEye!),
      if (f.noseBase != null) mPoint(f.noseBase!),
      if (f.mouthLeft != null) mPoint(f.mouthLeft!),
      if (f.mouthRight != null) mPoint(f.mouthRight!),
      if (f.mouthBottom != null) mPoint(f.mouthBottom!),
      if (f.leftCheek != null) mPoint(f.leftCheek!),
      if (f.rightCheek != null) mPoint(f.rightCheek!),
    ];
    for (final p in anchors) {
      canvas.drawCircle(p, 2.6, anchorPaint);
      canvas.drawCircle(
        p,
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent.withOpacity(0.4)
          ..strokeWidth = 1,
      );
    }

    // 6) Pulse halo around the face
    final pulseR = (ovalRect.width / 2) +
        8 +
        10 * (math.sin(t * 2 * math.pi) + 1) / 2;
    final pulseO = 0.15 + 0.4 * ((math.cos(t * 2 * math.pi) + 1) / 2);
    canvas.drawCircle(
      ovalRect.center,
      pulseR,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = accent.withOpacity(pulseO)
        ..strokeWidth = 1.2,
    );

    // 7) Bracket corners around face bbox — visual lock indicator.
    _drawBrackets(canvas, ovalRect.inflate(20), accent, locked);
  }

  void _paintPlaceholder(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.42;
    final accent = AppColors.primaryAccent.withOpacity(0.6);

    final ovalRect =
        Rect.fromCenter(center: Offset(cx, cy), width: 220, height: 300);
    final dash = Path();
    _addDashedOval(dash, ovalRect, dashWidth: 4, dashSpace: 5);
    canvas.drawPath(
      dash,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = accent
        ..strokeWidth = 1,
    );

    final pulseR = 145 + 12 * (math.sin(t * 2 * math.pi) + 1) / 2;
    final pulseO = 0.2 + 0.4 * ((math.cos(t * 2 * math.pi) + 1) / 2);
    canvas.drawCircle(
      Offset(cx, cy),
      pulseR,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.primaryAccent.withOpacity(pulseO)
        ..strokeWidth = 1.2,
    );

    _drawBrackets(
      canvas,
      Rect.fromLTRB(cx - 130, cy - 150, cx + 130, cy + 200),
      AppColors.primaryAccent,
      false,
    );
  }

  void _drawBrackets(Canvas canvas, Rect r, Color color, bool locked) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = locked ? 2.4 : 2
      ..strokeCap = StrokeCap.round;
    const len = 18.0;
    // top-left
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(len, 0), paint);
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(0, len), paint);
    // top-right
    canvas.drawLine(r.topRight, r.topRight + const Offset(-len, 0), paint);
    canvas.drawLine(r.topRight, r.topRight + const Offset(0, len), paint);
    // bottom-left
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(len, 0), paint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(0, -len), paint);
    // bottom-right
    canvas.drawLine(
        r.bottomRight, r.bottomRight + const Offset(-len, 0), paint);
    canvas.drawLine(
        r.bottomRight, r.bottomRight + const Offset(0, -len), paint);
  }

  Path _dashed(Path src, {required double dash, required double gap}) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final next = math.min(d + dash, m.length);
        out.addPath(m.extractPath(d, next), Offset.zero);
        d = next + gap;
      }
    }
    return out;
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
  bool shouldRepaint(covariant _FaceMeshPainter old) =>
      old.t != t ||
      old.face != face ||
      old.previewAspect != previewAspect ||
      old.locked != locked;
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
  const _LightStatusPill({required this.level});
  final _LightLevel level;

  @override
  Widget build(BuildContext context) {
    final color = level.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
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
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            level.label,
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
