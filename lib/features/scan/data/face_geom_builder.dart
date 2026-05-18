import 'dart:math' as math;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Builds the canonical `face_geom` JSON that the mobile client uploads
/// with every scan. Everything is in normalised image coordinates (0..1)
/// so the backend can store it once and every renderer (mobile result
/// screen, admin preview, …) can draw without needing the original
/// photo dimensions.
///
/// Shape:
/// ```
/// {
///   "bbox": [x0, y0, x1, y1],
///   "contour": [[x, y], [x, y], ...]?,
///   "landmarks": {
///     "forehead":    [x, y],
///     "tzone":       [x, y],
///     "left_cheek":  [x, y],
///     "right_cheek": [x, y],
///     "chin":        [x, y]
///   }?
/// }
/// ```
///
/// Returns null only when image dimensions are nonsensical. When the face
/// contour wasn't returned by ML Kit we still produce a bbox-only payload
/// so the renderer can synthesise an ellipse fallback.
Map<String, dynamic>? buildFaceGeomJson(
    Face face, double imgW, double imgH) {
  if (imgW <= 0 || imgH <= 0) return null;

  double nx(num v) => (v / imgW).clamp(0.0, 1.0);
  double ny(num v) => (v / imgH).clamp(0.0, 1.0);
  List<double> point(num x, num y) => [nx(x), ny(y)];

  final bbox = [
    nx(face.boundingBox.left),
    ny(face.boundingBox.top),
    nx(face.boundingBox.right),
    ny(face.boundingBox.bottom),
  ];

  final faceC = face.contours[FaceContourType.face]?.points;
  if (faceC == null || faceC.length < 8) {
    return {'bbox': bbox};
  }
  final contour = faceC
      .map((p) => point(p.x, p.y))
      .toList(growable: false);

  // ---- Derive zone landmarks from ML Kit data ----
  // We deliberately ignore FaceLandmarkType.leftCheek/rightCheek: those mark
  // the geometric centre of ML Kit's cheek region (basically under the eye,
  // near the nose) which doesn't line up with where dermatologists actually
  // assess "cheek" skin. Contour-derived points sit on the apple of the
  // cheek instead, which is what every other zone (forehead, T-zone, chin)
  // already does.
  final lBrow = face.contours[FaceContourType.leftEyebrowTop]?.points ?? [];
  final rBrow = face.contours[FaceContourType.rightEyebrowTop]?.points ?? [];
  final nose = face.contours[FaceContourType.noseBridge]?.points ?? [];
  final lowerLip =
      face.contours[FaceContourType.lowerLipBottom]?.points ?? [];

  final ys = contour.map((p) => p[1]).toList();
  final xs = contour.map((p) => p[0]).toList();
  final faceTop = ys.reduce(math.min);
  final faceBot = ys.reduce(math.max);
  final faceLeft = xs.reduce(math.min);
  final faceRight = xs.reduce(math.max);
  final faceH = faceBot - faceTop;
  final faceW = faceRight - faceLeft;
  final xMean = xs.reduce((a, b) => a + b) / contour.length;

  // Forehead — above brow midpoint. We lift by 14% face-h (was 18%, which
  // pushed the dot into the hairline for taller foreheads) and clamp so we
  // never go above bbox-top + 6%, otherwise long-haired users get a dot in
  // their hair.
  List<double> forehead;
  if (lBrow.isNotEmpty && rBrow.isNotEmpty) {
    final all = [...lBrow, ...rBrow];
    final cx = all.map((p) => p.x).reduce((a, b) => a + b) / all.length;
    final browYNorm =
        all.map((p) => p.y).reduce((a, b) => a + b) / all.length / imgH;
    final lifted = browYNorm - faceH * 0.14;
    final minY = faceTop + faceH * 0.06;
    forehead = [nx(cx), math.max(lifted, minY).clamp(0.0, 1.0)];
  } else {
    forehead = [xMean, (faceTop + faceH * 0.12).clamp(0.0, 1.0)];
  }

  // T-zone — middle of nose bridge.
  List<double> tzone;
  if (nose.isNotEmpty) {
    final mid = nose[nose.length ~/ 2];
    tzone = point(mid.x, mid.y);
  } else {
    tzone = [forehead[0], (forehead[1] + faceH * 0.30).clamp(0.0, 1.0)];
  }

  // Cheeks — apple of the cheek: vertically aligned with the bottom of the
  // nose bridge (about 60% down the face), horizontally pulled in 12% from
  // the contour edge so the dot sits on skin, not on the jaw line.
  double cheekY;
  if (nose.isNotEmpty) {
    // noseBridge bottom = nose tip → cheek apple is roughly at that Y.
    cheekY = nose.last.y / imgH;
  } else {
    cheekY = (faceTop + faceH * 0.55).clamp(0.0, 1.0);
  }
  // Find leftmost / rightmost contour points within a band around cheekY.
  // ±10% face-h is wide enough to find points even when contour is sparse.
  final band = contour
      .where((p) => (p[1] - cheekY).abs() < faceH * 0.10)
      .toList();
  List<double> leftCheek;
  List<double> rightCheek;
  if (band.length >= 2) {
    final lEdge = band.reduce((a, b) => a[0] < b[0] ? a : b);
    final rEdge = band.reduce((a, b) => a[0] > b[0] ? a : b);
    leftCheek = [
      (lEdge[0] + faceW * 0.12).clamp(0.0, 1.0),
      cheekY.clamp(0.0, 1.0),
    ];
    rightCheek = [
      (rEdge[0] - faceW * 0.12).clamp(0.0, 1.0),
      cheekY.clamp(0.0, 1.0),
    ];
  } else {
    leftCheek = [
      (faceLeft + faceW * 0.22).clamp(0.0, 1.0),
      cheekY.clamp(0.0, 1.0),
    ];
    rightCheek = [
      (faceRight - faceW * 0.22).clamp(0.0, 1.0),
      cheekY.clamp(0.0, 1.0),
    ];
  }

  // Chin — pad below the lower lip. The lower-lip contour gives us a stable
  // reference; we drop the dot ~45% of the way between lip and contour
  // bottom so it lands on the chin proper, not in the labio-mental crease
  // (the natural fold right under the lip) or on the throat.
  List<double> chin;
  final bottom = contour.reduce((a, b) => a[1] > b[1] ? a : b);
  if (lowerLip.isNotEmpty) {
    final lipY =
        lowerLip.map((p) => p.y).reduce(math.max) / imgH;
    final chinY = lipY + (bottom[1] - lipY) * 0.55;
    chin = [bottom[0], chinY.clamp(0.0, 1.0)];
  } else {
    chin = [bottom[0], (bottom[1] - faceH * 0.06).clamp(0.0, 1.0)];
  }

  return {
    'bbox': bbox,
    'contour': contour,
    'landmarks': {
      'forehead': forehead,
      'tzone': tzone,
      'left_cheek': leftCheek,
      'right_cheek': rightCheek,
      'chin': chin,
    },
  };
}
