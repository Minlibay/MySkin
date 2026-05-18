import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_settings/app_settings.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/telemetry/telemetry.dart';
import 'widgets/scan_camera_backdrop.dart';
import 'widgets/scan_face_overlay.dart' show DetectedFace;
import 'widgets/scan_overlay_widgets.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../api/backend_api.dart';
import '../data/face_geom_builder.dart';
import '../domain/scan_result.dart';

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

  LightLevel _light = LightLevel.unknown;
  // EMA of average luminance to avoid flicker.
  double _lumaEma = -1;

  DetectedFace? _face;
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
        // Accurate mode places eye/nose/mouth landmarks far more precisely
        // than fast mode at the cost of ~30-50ms/frame — fine because we
        // throttle to every 3rd frame anyway.
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.2,
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
        ? LightLevel.tooDark
        : _lumaEma > 215
            ? LightLevel.tooBright
            : LightLevel.ok;
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
      final leftEyeContour = f.contours[FaceContourType.leftEye]?.points;
      final rightEyeContour = f.contours[FaceContourType.rightEye]?.points;
      // Eye centroid from the 16-point contour beats the single-landmark
      // approximation by a wide margin: the landmark sits near the brow
      // sometimes, the centroid lands on the pupil consistently.
      final leftEyePos = _centroid(leftEyeContour) ??
          f.landmarks[FaceLandmarkType.leftEye]?.position;
      final rightEyePos = _centroid(rightEyeContour) ??
          f.landmarks[FaceLandmarkType.rightEye]?.position;
      final detected = DetectedFace(
        bounds: f.boundingBox,
        imageSize: rotated,
        mirror: desc.lensDirection == CameraLensDirection.front,
        leftEye: leftEyePos,
        rightEye: rightEyePos,
        noseBase: f.landmarks[FaceLandmarkType.noseBase]?.position,
        mouthLeft: f.landmarks[FaceLandmarkType.leftMouth]?.position,
        mouthRight: f.landmarks[FaceLandmarkType.rightMouth]?.position,
        mouthBottom: f.landmarks[FaceLandmarkType.bottomMouth]?.position,
        leftCheek: f.landmarks[FaceLandmarkType.leftCheek]?.position,
        rightCheek: f.landmarks[FaceLandmarkType.rightCheek]?.position,
        faceContour: f.contours[FaceContourType.face]?.points,
        leftEyeContour: leftEyeContour,
        rightEyeContour: rightEyeContour,
        upperLipTop: f.contours[FaceContourType.upperLipTop]?.points,
        lowerLipBottom: f.contours[FaceContourType.lowerLipBottom]?.points,
        noseBridge: f.contours[FaceContourType.noseBridge]?.points,
      );
      _faceSeenAt = DateTime.now();
      // Blend with the previous frame to suppress per-frame jitter on the
      // landmarks — the painter still snaps to a new face on big jumps.
      final smoothed = _blendFaces(_face, detected, alpha: 0.55);
      setState(() => _face = smoothed);
    } catch (e) {
      debugPrint('Face detect error: $e');
    }
  }

  math.Point<int>? _centroid(List<math.Point<int>>? pts) {
    if (pts == null || pts.isEmpty) return null;
    var sx = 0, sy = 0;
    for (final p in pts) {
      sx += p.x;
      sy += p.y;
    }
    return math.Point(sx ~/ pts.length, sy ~/ pts.length);
  }

  /// Per-landmark EMA: blends previous smoothed face with the fresh
  /// detection. Falls back to the new face when no prior frame, when
  /// image geometry changed, or when the face moved far enough that
  /// blending would visibly drag behind (>20% of face width).
  DetectedFace _blendFaces(
      DetectedFace? prev, DetectedFace next, {required double alpha}) {
    if (prev == null ||
        prev.imageSize != next.imageSize ||
        prev.mirror != next.mirror) {
      return next;
    }
    final dx = (prev.bounds.center.dx - next.bounds.center.dx).abs();
    final dy = (prev.bounds.center.dy - next.bounds.center.dy).abs();
    final jumpThreshold = next.bounds.width * 0.2;
    if (dx > jumpThreshold || dy > jumpThreshold) return next;

    math.Point<int>? lp(math.Point<int>? a, math.Point<int>? b) {
      if (a == null) return b;
      if (b == null) return a;
      return math.Point(
        (a.x * alpha + b.x * (1 - alpha)).round(),
        (a.y * alpha + b.y * (1 - alpha)).round(),
      );
    }

    Rect lb(Rect a, Rect b) => Rect.fromLTRB(
          a.left * alpha + b.left * (1 - alpha),
          a.top * alpha + b.top * (1 - alpha),
          a.right * alpha + b.right * (1 - alpha),
          a.bottom * alpha + b.bottom * (1 - alpha),
        );

    return DetectedFace(
      bounds: lb(prev.bounds, next.bounds),
      imageSize: next.imageSize,
      mirror: next.mirror,
      leftEye: lp(prev.leftEye, next.leftEye),
      rightEye: lp(prev.rightEye, next.rightEye),
      noseBase: lp(prev.noseBase, next.noseBase),
      mouthLeft: lp(prev.mouthLeft, next.mouthLeft),
      mouthRight: lp(prev.mouthRight, next.mouthRight),
      mouthBottom: lp(prev.mouthBottom, next.mouthBottom),
      leftCheek: lp(prev.leftCheek, next.leftCheek),
      rightCheek: lp(prev.rightCheek, next.rightCheek),
      // Contours move with the face; snapping to the new ones is fine —
      // smoothing them point-by-point is expensive and contours are
      // already low-frequency relative to the landmark dots.
      faceContour: next.faceContour,
      leftEyeContour: next.leftEyeContour,
      rightEyeContour: next.rightEyeContour,
      upperLipTop: next.upperLipTop,
      lowerLipBottom: next.lowerLipBottom,
      noseBridge: next.noseBridge,
    );
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
    if (_light == LightLevel.tooDark) {
      return 'Темновато — найди свет поярче';
    }
    if (_light == LightLevel.tooBright) {
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
    if (_light == LightLevel.tooDark) {
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
      // Detect face directly on the saved photo. Far more accurate than
      // re-using the stream bbox because the still picture and the preview
      // frames have different FOVs / aspect ratios — a stream bbox would
      // land in the wrong place once we project it onto the photo.
      final faceGeom = await _faceGeomFromFile(pic.path, bytes);
      await _uploadAndFinish(bytes, mime: 'image/jpeg', faceGeom: faceGeom);
    } on ScanQualityException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      await _startStream();
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
      // Same as the camera path — run ML Kit on the chosen file so the
      // server gets the full face_geom (polygon + landmarks) and the
      // result screen never needs to re-detect.
      final faceGeom = await _faceGeomFromFile(picked.path, bytes);
      await _uploadAndFinish(bytes,
          mime: picked.mimeType ?? 'image/jpeg', faceGeom: faceGeom);
    } on ScanQualityException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не получилось загрузить: $e';
      });
    }
  }

  Future<void> _uploadAndFinish(List<int> bytes,
      {required String mime, Map<String, dynamic>? faceGeom}) async {
    final b64 = base64Encode(bytes);
    final result = await ref.read(backendApiProvider).uploadScan(
          photoBase64: b64,
          mime: mime,
          faceGeom: faceGeom,
        );
    Telemetry.event('scan_uploaded', data: {
      'photo_kb': (bytes.length / 1024).round(),
      'score': result.score,
      'had_face_geom': faceGeom != null,
      'had_face_contour': faceGeom?['contour'] != null,
    });
    if (!mounted) return;
    widget.onResult(result);
  }

  /// Run ML Kit on the saved photo file and normalise the bbox into [0..1]
  /// against the decoded photo's pixel dimensions. EXIF rotation is honoured
  /// by InputImage.fromFilePath and by Flutter's image decoder, so the
  /// resulting rect lines up with how the photo is later displayed.
  /// Detects the user's face on a saved photo and produces the full
  /// `face_geom` payload. We deliberately do NOT reuse [_faceDetector]
  /// here — it has `enableTracking: true` for the live preview, and per
  /// ML Kit docs tracking conflicts with contour detection on single
  /// images (iOS silently returns no faces). Each pass below builds a
  /// fresh detector with the right options.
  ///
  /// 3-pass cascade:
  ///   1. accurate + contours + landmarks @ 0.15  ← preferred (full data)
  ///   2. accurate + landmarks only       @ 0.08
  ///   3. fast, plain                     @ 0.05  ← last resort
  Future<Map<String, dynamic>?> _faceGeomFromFile(
      String path, List<int> bytes) async {
    final size = await _decodedImageSize(Uint8List.fromList(bytes));
    if (size == null) {
      Telemetry.event('scan_face_detect',
          data: {'outcome': 'decode_failed'});
      return null;
    }

    Face? face = await _runDetector(
      FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableContours: true,
          enableLandmarks: true,
          minFaceSize: 0.15,
        ),
      ),
      path,
      pass: 'accurate_contours_015',
      dispose: true,
    );
    face ??= await _runDetector(
      FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableLandmarks: true,
          minFaceSize: 0.08,
        ),
      ),
      path,
      pass: 'accurate_landmarks_008',
      dispose: true,
    );
    face ??= await _runDetector(
      FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.05,
        ),
      ),
      path,
      pass: 'fast_005',
      dispose: true,
    );
    if (face == null) {
      Telemetry.event('scan_face_detect', data: {
        'outcome': 'no_face',
        'image_w': size.width.toInt(),
        'image_h': size.height.toInt(),
      });
      return null;
    }
    final geom = buildFaceGeomJson(face, size.width, size.height);
    Telemetry.event('scan_face_detect', data: {
      'outcome': 'ok',
      'has_contour': geom?['contour'] != null,
      'image_w': size.width.toInt(),
      'image_h': size.height.toInt(),
    });
    return geom;
  }

  Future<Face?> _runDetector(
    FaceDetector detector,
    String path, {
    String pass = '',
    bool dispose = false,
  }) async {
    try {
      final input = InputImage.fromFilePath(path);
      final faces = await detector.processImage(input);
      if (faces.isEmpty) {
        debugPrint('face detect pass=$pass returned 0 faces');
        return null;
      }
      faces.sort((a, b) =>
          (b.boundingBox.width * b.boundingBox.height)
              .compareTo(a.boundingBox.width * a.boundingBox.height));
      debugPrint(
          'face detect pass=$pass found ${faces.length} face(s)');
      return faces.first;
    } catch (e) {
      debugPrint('face detect pass=$pass failed: $e');
      return null;
    } finally {
      if (dispose) await detector.close();
    }
  }

  Future<({double width, double height})?> _decodedImageSize(
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
    return Scaffold(
      backgroundColor: const Color(0xFF0F0A0C),
      body: Stack(
        children: [
          Positioned.fill(
            child: ScanCameraBackdrop(
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
          // Face-mesh overlay deliberately removed — the live mesh felt
          // intrusive on top of a self-portrait, and the alignment value it
          // gave the user wasn't worth the visual cost. The detected face
          // still drives the locked/ok states for hints and capture timing,
          // it just isn't drawn on screen anymore.
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        GlassButton(
                          icon: Icons.close_rounded,
                          onTap: widget.onBack,
                        ),
                        const Spacer(),
                        LightStatusPill(level: _light),
                        const Spacer(),
                        GlassButton(
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
                          if (_cameraError != null &&
                              _cameraError!
                                  .toLowerCase()
                                  .contains('нет доступа'))
                            _SettingsCta(
                              onTap: () =>
                                  AppSettings.openAppSettings(),
                            )
                          else
                            ShutterButton(
                                busy: _busy, onTap: _capture),
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

/// Replacement for the shutter button when camera permission was denied.
/// Opens the OS app-settings so the user can grant access without leaving
/// the app for a third-party flow.
class _SettingsCta extends StatelessWidget {
  const _SettingsCta({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings_outlined, size: 18, color: AppColors.roseDeep),
              const SizedBox(width: 6),
              Text(
                'Настройки',
                style: AppTypography.bodyMedium.copyWith(
                  fontSize: 14,
                  color: AppColors.roseDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

