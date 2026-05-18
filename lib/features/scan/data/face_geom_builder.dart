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
  // Two hard rules behind the formulas below:
  //
  // 1. Use only point landmarks (eyes, noseBase, mouth). Anything derived
  //    from the face *contour* or even the bounding box gets dragged off
  //    on bearded/long-haired users — ML Kit traces the silhouette around
  //    hair/beard, so the box bottom can sit on the chest.
  //
  // 2. Apply offsets in the SAME axis they were measured on. Mixing an
  //    x-normalised distance into a y-normalised lift (as a previous
  //    revision did) silently scales by the photo aspect ratio — in
  //    portrait mode (9:16) the lift then doubles and the forehead dot
  //    lands in the hair.
  //
  // The "rule of thirds" of the face — eye line → nose base → chin tip
  // are equal vertical thirds — is what anchors everything. eyeMidY and
  // noseBaseY are robust, and their difference gives us a unit ruler in
  // y-space that's beard-independent.
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

  // The "third" is the vertical distance from the eye line to the bottom
  // of the nose. Forehead, t-zone and chin are all expressed in multiples
  // of this single unit.
  double? eyeMidX, eyeMidY, third;
  if (lEye != null && rEye != null) {
    eyeMidX = (lEye.x + rEye.x) / 2 / imgW;
    eyeMidY = (lEye.y + rEye.y) / 2 / imgH;
    if (noseBase != null) {
      third = (noseBase.y / imgH) - eyeMidY;
      if (third <= 0) third = null; // sanity: nose below eyes only
    }
  }

  // Forehead — one "third" above the eye line. Clamp so we never go above
  // the bbox top (would put the dot in the hair).
  List<double> forehead;
  if (eyeMidX != null && eyeMidY != null && third != null) {
    final y = eyeMidY - third;
    final minY = bboxTop + 0.02;
    forehead = [eyeMidX.clamp(0.0, 1.0), math.max(y, minY).clamp(0.0, 1.0)];
  } else {
    forehead = [bboxCx, (bboxTop + bboxH * 0.18).clamp(0.0, 1.0)];
  }

  // T-zone — bridge of the nose, ~40% of the way from eyes to nose base.
  List<double> tzone;
  if (eyeMidX != null && eyeMidY != null && third != null) {
    tzone = [
      eyeMidX.clamp(0.0, 1.0),
      (eyeMidY + third * 0.40).clamp(0.0, 1.0),
    ];
  } else {
    tzone = [bboxCx, (bboxTop + bboxH * 0.42).clamp(0.0, 1.0)];
  }

  // Cheeks — the upper cheek (zygomatic prominence). Y is halfway between
  // eye line and nose base; X = pupil X. Going lower than the nose base
  // lands the dot in the beard for thickly bearded users, so we stay at
  // mid-cheek where visible skin survives even on a heavy beard.
  List<double> leftCheek;
  List<double> rightCheek;
  if (lEye != null && rEye != null && third != null && eyeMidY != null) {
    final cheekY = (eyeMidY + third * 0.55).clamp(0.0, 1.0);
    leftCheek = [(lEye.x / imgW).clamp(0.0, 1.0), cheekY];
    rightCheek = [(rEye.x / imgW).clamp(0.0, 1.0), cheekY];
  } else {
    leftCheek = [
      (bboxLeft + bboxW * 0.25).clamp(0.0, 1.0),
      (bboxTop + bboxH * 0.50).clamp(0.0, 1.0),
    ];
    rightCheek = [
      (bboxRight - bboxW * 0.25).clamp(0.0, 1.0),
      (bboxTop + bboxH * 0.50).clamp(0.0, 1.0),
    ];
  }

  // Chin — one "third" below the nose base (rule of thirds). NO bbox use,
  // so beards/necks that stretch the bbox can't drag the dot down. X from
  // the mouth midpoint if available, else eye midpoint.
  List<double> chin;
  if (noseBase != null && third != null) {
    final chinY = (noseBase.y / imgH + third).clamp(0.0, 1.0);
    double cx;
    if (mouthLeft != null && mouthRight != null) {
      cx = ((mouthLeft.x + mouthRight.x) / 2) / imgW;
    } else if (mouthBot != null) {
      cx = mouthBot.x / imgW;
    } else {
      cx = eyeMidX ?? bboxCx;
    }
    chin = [cx.clamp(0.0, 1.0), chinY];
  } else {
    chin = [bboxCx, (bboxTop + bboxH * 0.88).clamp(0.0, 1.0)];
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
