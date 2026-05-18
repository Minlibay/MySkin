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

  // ---- Derive zone landmarks from ML Kit DIRECT landmarks ----
  // We deliberately avoid the face contour for placing zone dots. The
  // contour traces hair and beard outlines on real users (the outline
  // around the face polygon, not the underlying skull), so any landmark
  // derived from it — contour-bottom, contour-width, contour-height —
  // gets dragged off-face for anyone with a beard or long hair. ML Kit's
  // point landmarks (eyes, nose base, mouth) are stable: they're keyed to
  // recognisable features, not the silhouette.
  final lm = face.landmarks;
  final lEye = lm[FaceLandmarkType.leftEye]?.position;
  final rEye = lm[FaceLandmarkType.rightEye]?.position;
  final noseBase = lm[FaceLandmarkType.noseBase]?.position;
  final mouthLeft = lm[FaceLandmarkType.leftMouth]?.position;
  final mouthRight = lm[FaceLandmarkType.rightMouth]?.position;
  final mouthBot = lm[FaceLandmarkType.bottomMouth]?.position;

  final bboxTop = ny(face.boundingBox.top);
  final bboxBot = ny(face.boundingBox.bottom);
  final bboxLeft = nx(face.boundingBox.left);
  final bboxRight = nx(face.boundingBox.right);
  final bboxH = bboxBot - bboxTop;
  final bboxW = bboxRight - bboxLeft;
  final bboxCx = (bboxLeft + bboxRight) / 2;

  // Forehead — above the brow line. If we have eyes, lift from the eye
  // baseline by roughly 1× eye-to-eye distance (the average distance from
  // pupil to mid-forehead). If only the bbox is available, drop to a
  // fraction of bbox height with a hard upper bound so longer hair never
  // pushes the dot off-face.
  List<double> forehead;
  if (lEye != null && rEye != null) {
    final eyeMidX = (lEye.x + rEye.x) / 2 / imgW;
    final eyeMidY = (lEye.y + rEye.y) / 2 / imgH;
    final eyeSpan = (rEye.x - lEye.x).abs() / imgW;
    final yLifted = eyeMidY - eyeSpan * 0.95;
    final minY = bboxTop + bboxH * 0.08;
    forehead = [eyeMidX.clamp(0.0, 1.0), math.max(yLifted, minY).clamp(0.0, 1.0)];
  } else {
    forehead = [bboxCx, (bboxTop + bboxH * 0.18).clamp(0.0, 1.0)];
  }

  // T-zone — between the eyes on the nose bridge. Eye midpoint horizontal,
  // halfway down to noseBase vertically (so it lands above the tip, on the
  // bridge).
  List<double> tzone;
  if (lEye != null && rEye != null) {
    final eyeMidX = (lEye.x + rEye.x) / 2 / imgW;
    final eyeMidY = (lEye.y + rEye.y) / 2 / imgH;
    final noseY = noseBase != null ? noseBase.y / imgH : eyeMidY + bboxH * 0.18;
    tzone = [
      eyeMidX.clamp(0.0, 1.0),
      ((eyeMidY + noseY) / 2).clamp(0.0, 1.0),
    ];
  } else {
    tzone = [bboxCx, (bboxTop + bboxH * 0.42).clamp(0.0, 1.0)];
  }

  // Cheeks — apple of the cheek sits directly below the eye, at roughly
  // nose-base height. X = eye.x (slightly pulled toward bbox edge to be
  // safely on cheek skin, not on the side of the nose). Y = noseBase.y
  // (lower than the eye-bottom, where the cheek's volume is greatest).
  List<double> leftCheek;
  List<double> rightCheek;
  if (lEye != null && rEye != null && noseBase != null) {
    final lEyeX = lEye.x / imgW;
    final rEyeX = rEye.x / imgW;
    final noseY = noseBase.y / imgH;
    // Pull each cheek 25% of the eye-to-bbox-edge distance toward the
    // outside — this nudges the dot off the side of the nose onto the
    // cheek proper. ML Kit's eye landmarks sit at pupil centre.
    final lOut = (bboxLeft - lEyeX) * 0.25;
    final rOut = (bboxRight - rEyeX) * 0.25;
    leftCheek = [(lEyeX + lOut).clamp(0.0, 1.0), noseY.clamp(0.0, 1.0)];
    rightCheek = [(rEyeX + rOut).clamp(0.0, 1.0), noseY.clamp(0.0, 1.0)];
  } else {
    leftCheek = [
      (bboxLeft + bboxW * 0.25).clamp(0.0, 1.0),
      (bboxTop + bboxH * 0.55).clamp(0.0, 1.0),
    ];
    rightCheek = [
      (bboxRight - bboxW * 0.25).clamp(0.0, 1.0),
      (bboxTop + bboxH * 0.55).clamp(0.0, 1.0),
    ];
  }

  // Chin — below the mouth. Best anchor is the mouth-bottom landmark plus
  // a third of the mouth-to-bbox-bottom gap (lands on chin pad, not in
  // the labio-mental crease right under the lip). Hard-cap at 1% inside
  // bbox.bottom so it never escapes onto the throat/chest, even if our
  // mouth landmarks were off.
  List<double> chin;
  if (mouthBot != null) {
    final mxNum = (mouthLeft != null && mouthRight != null)
        ? (mouthLeft.x + mouthRight.x) / 2
        : mouthBot.x.toDouble();
    final mouthBy = mouthBot.y / imgH;
    final gap = bboxBot - mouthBy;
    final chinY = (mouthBy + gap * 0.55).clamp(0.0, bboxBot - 0.01);
    chin = [nx(mxNum), chinY];
  } else {
    chin = [bboxCx, (bboxTop + bboxH * 0.88).clamp(0.0, bboxBot - 0.01)];
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
