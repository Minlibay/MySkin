import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Snapshot of the latest detected face, in image-coordinates (already
/// rotated to upright by ML Kit). The painter projects these onto the
/// canvas using the preview rect derived from [FaceMeshPainter._previewRect].
class DetectedFace {
  DetectedFace({
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

/// Custom painter overlay that renders the dashed face oval, ML Kit
/// landmark mesh, eye + lip contours, anchor dots, pulsing halo, and
/// corner brackets — all driven by [t] (0..1 animation tick) and the
/// most recent [face] snapshot.
class FaceMeshPainter extends CustomPainter {
  FaceMeshPainter({
    required this.t,
    required this.face,
    required this.previewAspect,
    required this.locked,
  });

  final double t;
  final DetectedFace? face;
  final double previewAspect;
  final bool locked;

  /// On-screen rect occupied by the camera preview. ScanCameraBackdrop wraps
  /// the preview in `FittedBox(fit: cover, child: SizedBox(width=W,
  /// height=W*aspect))` — so the actual rendered rect is the cover-scaled
  /// version of that SizedBox, not the SizedBox itself. The old code mapped
  /// landmarks onto the un-scaled SizedBox, which on tall phones is far
  /// narrower and shorter than the visible preview — face overlay drifted to
  /// the edge and shrank.
  Rect _previewRect(Size canvas) {
    final cw = canvas.width;
    final ch = canvas.width * previewAspect;
    final s = math.max(canvas.width / cw, canvas.height / ch);
    final w = cw * s;
    final h = ch * s;
    return Rect.fromLTWH(
      (canvas.width - w) / 2,
      (canvas.height - h) / 2,
      w,
      h,
    );
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
    final left =
        f.mirror ? f.imageSize.width - f.bounds.right : f.bounds.left;
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

    final accent = locked ? AppColors.success : AppColors.primaryAccent;

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
  bool shouldRepaint(covariant FaceMeshPainter old) =>
      old.t != t ||
      old.face != face ||
      old.previewAspect != previewAspect ||
      old.locked != locked;
}
