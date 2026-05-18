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

  // Cheeks and chin used to be derived from the face contour (cheek edges
  // pulled in from leftmost/rightmost contour points; chin a fraction of
  // the way down to the contour bottom). That breaks badly on bearded
  // faces because ML Kit traces the contour around the beard, so both
  // faceH and the contour bottom run far past the actual jaw. We now
  // anchor cheeks and chin to facial proportions instead — brows, nose
  // tip and lower lip don't move with hair/beard volume.

  // Inter-brow midpoint and brow width — stable face-size reference that
  // ignores beards/hairlines. Brow width here = horizontal span of both
  // brows combined, which is close to inter-pupillary × 2.4.
  double? browMidX;
  double? browWidth;
  if (lBrow.isNotEmpty && rBrow.isNotEmpty) {
    final lx = lBrow.map((p) => p.x.toDouble()).toList();
    final rx = rBrow.map((p) => p.x.toDouble()).toList();
    final lMean = lx.reduce((a, b) => a + b) / lx.length / imgW;
    final rMean = rx.reduce((a, b) => a + b) / rx.length / imgW;
    browMidX = (lMean + rMean) / 2;
    browWidth = (rMean - lMean).abs();
  }

  // Nose tip Y (bottom of nose bridge contour) anchors the cheek-apple
  // height; nose top Y anchors chin via rule-of-thirds.
  final noseTipY = nose.isNotEmpty ? nose.last.y / imgH : null;
  final noseTopY = nose.isNotEmpty ? nose.first.y / imgH : null;

  // Cheeks — at nose tip height, offset from the face midline by half a
  // brow-width on each side. Falls back to bbox-based positions only when
  // brow/nose contours are missing.
  double cheekY = noseTipY ?? (faceTop + faceH * 0.55);
  List<double> leftCheek;
  List<double> rightCheek;
  if (browMidX != null && browWidth != null && browWidth > 0) {
    final dx = browWidth * 0.50;
    leftCheek = [(browMidX - dx).clamp(0.0, 1.0), cheekY.clamp(0.0, 1.0)];
    rightCheek = [(browMidX + dx).clamp(0.0, 1.0), cheekY.clamp(0.0, 1.0)];
  } else {
    leftCheek = [
      (faceLeft + faceW * 0.25).clamp(0.0, 1.0),
      cheekY.clamp(0.0, 1.0),
    ];
    rightCheek = [
      (faceRight - faceW * 0.25).clamp(0.0, 1.0),
      cheekY.clamp(0.0, 1.0),
    ];
  }

  // Chin — rule of thirds: lip-to-chin distance ≈ nose-top-to-lip distance.
  // This holds regardless of beard volume. Falls back to lip + a small
  // bbox-relative pad when nose/lip contours are missing.
  List<double> chin;
  if (lowerLip.isNotEmpty) {
    final lipBottomY =
        lowerLip.map((p) => p.y).reduce(math.max) / imgH;
    final lipMeanX =
        lowerLip.map((p) => p.x).reduce((a, b) => a + b) /
            lowerLip.length /
            imgW;
    double chinY;
    if (noseTopY != null) {
      // Distance from nose-top to lower-lip equals lower-lip to chin tip.
      chinY = lipBottomY + (lipBottomY - noseTopY);
    } else {
      chinY = lipBottomY + faceH * 0.10;
    }
    // Don't let chin pop below the face bbox — that would put it on the
    // throat/chest even when our proportions go a bit off.
    final bboxBot = ny(face.boundingBox.bottom);
    chin = [
      lipMeanX.clamp(0.0, 1.0),
      math.min(chinY, bboxBot - 0.01).clamp(0.0, 1.0),
    ];
  } else {
    final bottom = contour.reduce((a, b) => a[1] > b[1] ? a : b);
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
