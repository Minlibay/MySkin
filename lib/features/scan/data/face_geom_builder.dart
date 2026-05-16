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
  final lBrow = face.contours[FaceContourType.leftEyebrowTop]?.points ?? [];
  final rBrow = face.contours[FaceContourType.rightEyebrowTop]?.points ?? [];
  final nose = face.contours[FaceContourType.noseBridge]?.points ?? [];
  final lCheekL = face.landmarks[FaceLandmarkType.leftCheek];
  final rCheekL = face.landmarks[FaceLandmarkType.rightCheek];

  final ys = contour.map((p) => p[1]);
  final xs = contour.map((p) => p[0]);
  final faceTop = ys.reduce(math.min);
  final faceBot = ys.reduce(math.max);
  final faceH = faceBot - faceTop;
  final xMean = xs.reduce((a, b) => a + b) / contour.length;

  // Forehead — above midpoint of the two eyebrows, lifted by ~18% face h.
  List<double> forehead;
  if (lBrow.isNotEmpty && rBrow.isNotEmpty) {
    final all = [...lBrow, ...rBrow];
    final cx = all.map((p) => p.x).reduce((a, b) => a + b) / all.length;
    final cy = all.map((p) => p.y).reduce((a, b) => a + b) / all.length;
    forehead = [nx(cx), ((cy / imgH) - faceH * 0.18).clamp(0.0, 1.0)];
  } else {
    forehead = [xMean, (faceTop + faceH * 0.10).clamp(0.0, 1.0)];
  }

  // T-zone — middle of nose bridge.
  List<double> tzone;
  if (nose.isNotEmpty) {
    final mid = nose[nose.length ~/ 2];
    tzone = point(mid.x, mid.y);
  } else {
    tzone = [forehead[0], (forehead[1] + faceH * 0.30).clamp(0.0, 1.0)];
  }

  // Cheeks — explicit landmarks or extreme contour points at cheekbone Y.
  List<double> leftCheek;
  if (lCheekL != null) {
    leftCheek = point(lCheekL.position.x, lCheekL.position.y);
  } else {
    final lp = contour.reduce((a, b) => a[0] < b[0] ? a : b);
    leftCheek = [
      (lp[0] + 0.03).clamp(0.0, 1.0),
      (tzone[1] + faceH * 0.05).clamp(0.0, 1.0),
    ];
  }
  List<double> rightCheek;
  if (rCheekL != null) {
    rightCheek = point(rCheekL.position.x, rCheekL.position.y);
  } else {
    final rp = contour.reduce((a, b) => a[0] > b[0] ? a : b);
    rightCheek = [
      (rp[0] - 0.03).clamp(0.0, 1.0),
      (tzone[1] + faceH * 0.05).clamp(0.0, 1.0),
    ];
  }

  // Chin — lowest contour point, raised slightly so the blob sits on the
  // chin rather than the throat below it.
  final bottom = contour.reduce((a, b) => a[1] > b[1] ? a : b);
  final chin = [bottom[0], (bottom[1] - faceH * 0.04).clamp(0.0, 1.0)];

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
