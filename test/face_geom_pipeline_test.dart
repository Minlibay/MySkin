// Pure-Dart pipeline test: builder → JSON → FaceGeometry → roundtrip.
// We don't instantiate a real ML Kit Face here (the package needs platform
// channels), so we exercise the validated paths directly: build a payload
// shape that matches what buildFaceGeomJson would emit, then make sure
// it survives JSON ser/deser and arrives at FaceGeometry intact.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myskin/features/scan/domain/scan_result.dart';

void main() {
  group('FaceGeometry.tryFromJson', () {
    test('parses the full payload buildFaceGeomJson produces', () {
      // Synthetic payload in the exact shape the mobile builder emits.
      // Bbox, ~30-point contour, all 5 landmarks. All normalised.
      final contour = List.generate(36, (i) {
        final t = i / 36;
        return [0.3 + t * 0.4, 0.2 + t * 0.5];
      });
      final original = {
        'bbox': [0.25, 0.15, 0.75, 0.85],
        'contour': contour,
        'landmarks': {
          'forehead': [0.5, 0.22],
          'tzone': [0.5, 0.5],
          'left_cheek': [0.35, 0.6],
          'right_cheek': [0.65, 0.6],
          'chin': [0.5, 0.82],
        },
      };

      // Survives a JSON round-trip (this is what the network does).
      final encoded = jsonEncode(original);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      final geom = FaceGeometry.tryFromJson(decoded);
      expect(geom, isNotNull);
      expect(geom!.bbox, [0.25, 0.15, 0.75, 0.85]);
      expect(geom.contour, isNotNull);
      expect(geom.contour!.length, 36);
      expect(geom.landmarks, isNotNull);
      expect(geom.landmarks!['forehead'], [0.5, 0.22]);
      expect(geom.landmarks!['chin'], [0.5, 0.82]);
    });

    test('falls back to bbox-only when contour/landmarks missing', () {
      final geom = FaceGeometry.tryFromJson({
        'bbox': [0.2, 0.1, 0.8, 0.9],
      });
      expect(geom, isNotNull);
      expect(geom!.contour, isNull);
      expect(geom.landmarks, isNull);
    });

    test('rejects malformed bbox', () {
      expect(FaceGeometry.tryFromJson({'bbox': [0.2, 0.1, 0.1, 0.9]}),
          isNull,
          reason: 'x1 must be > x0');
      expect(FaceGeometry.tryFromJson({'bbox': [0.2, 0.9, 0.8, 0.1]}),
          isNull,
          reason: 'y1 must be > y0');
      expect(FaceGeometry.tryFromJson({'bbox': [0.2, 0.1]}), isNull,
          reason: 'must have 4 entries');
      expect(FaceGeometry.tryFromJson({'foo': 'bar'}), isNull);
      expect(FaceGeometry.tryFromJson(null), isNull);
    });

    test('drops contour with fewer than 8 points', () {
      final geom = FaceGeometry.tryFromJson({
        'bbox': [0.25, 0.15, 0.75, 0.85],
        'contour': [
          [0.3, 0.2],
          [0.4, 0.2],
          [0.5, 0.3],
        ],
      });
      expect(geom, isNotNull);
      expect(geom!.contour, isNull,
          reason: 'too few points to draw an outline');
    });

    test('drops landmarks if any zone key is missing', () {
      final geom = FaceGeometry.tryFromJson({
        'bbox': [0.25, 0.15, 0.75, 0.85],
        'landmarks': {
          'forehead': [0.5, 0.22],
          'tzone': [0.5, 0.5],
          // missing left_cheek/right_cheek/chin
        },
      });
      expect(geom, isNotNull);
      expect(geom!.landmarks, isNull,
          reason: 'partial landmarks would mispaint the heatmap');
    });

    test('clamps coordinates outside [0,1]', () {
      final geom = FaceGeometry.tryFromJson({
        'bbox': [-0.1, -0.2, 1.5, 1.5],
      });
      expect(geom, isNotNull);
      expect(geom!.bbox, [0.0, 0.0, 1.0, 1.0]);
    });
  });
}
