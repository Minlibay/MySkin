import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../api/backend_api.dart';
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
  Future<void>? _initFuture;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _initFuture = _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
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
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _camera = ctrl;
        _cameraError = null;
      });
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

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) {
      // Camera not ready — fall back to gallery so the user isn't stuck.
      return _pickFromGallery();
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pic = await cam.takePicture();
      final bytes = await File(pic.path).readAsBytes();
      await _uploadAndFinish(bytes, mime: 'image/jpeg');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не получилось снять: $e';
      });
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
    return Scaffold(
      backgroundColor: const Color(0xFF0F0A0C),
      body: Stack(
        children: [
          // Live camera feed (or dark fallback while initialising / on error)
          Positioned.fill(child: _CameraBackdrop(
            controller: _camera,
            initFuture: _initFuture,
            errorText: _cameraError,
          )),
          // dark vignette so the mesh is readable on bright frames
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
          // face mesh overlay
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => CustomPaint(
                  painter: _FaceMeshPainter(t: _pulse.value),
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
                        _LightStatusPill(),
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
        // `aspectRatio` from the camera plugin is the sensor's native
        // (landscape) ratio, e.g. 16:9 ≈ 1.78. On a portrait screen we want
        // the rotated dimensions, so multiply width by aspectRatio to get
        // the portrait height. FittedBox.cover then crops sides instead of
        // stretching the face horizontally.
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

class _FaceMeshPainter extends CustomPainter {
  _FaceMeshPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.42;

    final ovalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.primaryAccent.withOpacity(0.7)
      ..strokeWidth = 1;
    final dash = Path();
    final ovalRect =
        Rect.fromCenter(center: Offset(cx, cy), width: 220, height: 300);
    _addDashedOval(dash, ovalRect, dashWidth: 4, dashSpace: 5);
    canvas.drawPath(dash, ovalPaint);

    final mesh = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.primaryAccent.withOpacity(0.4)
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

    final pulseR = 145 + 12 * (math.sin(t * 2 * math.pi) + 1) / 2;
    final pulseO = 0.2 + 0.5 * ((math.cos(t * 2 * math.pi) + 1) / 2);
    final pulse = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.primaryAccent.withOpacity(pulseO)
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset(cx, cy), pulseR, pulse);

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
