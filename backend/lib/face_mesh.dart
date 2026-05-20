import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Thin HTTP client for the MediaPipe Face Mesh sidecar.
///
/// Single endpoint `POST /detect` (raw image bytes in body) returns a
/// face_geom payload in normalised 0..1 coordinates — the exact shape the
/// mobile renderer expects:
///
/// ```
/// { "found": true,
///   "bbox": [x0, y0, x1, y1],
///   "contour": [[x, y], ...],
///   "landmarks": { "forehead":[x,y], "tzone":[x,y],
///                  "left_cheek":[x,y], "right_cheek":[x,y], "chin":[x,y] } }
/// ```
///
/// Returns `null` for any non-200, network failure, missing face, or
/// malformed payload — callers treat null as "no face detected" and
/// surface that to the user.
class FaceMeshClient {
  FaceMeshClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 8),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _http;

  bool get configured => baseUrl.isNotEmpty;

  /// Detect face landmarks for the given image bytes. Returns the parsed
  /// payload on success, null on no_face / error.
  Future<Map<String, dynamic>?> detect(List<int> photoBytes) async {
    if (!configured) return null;
    if (photoBytes.isEmpty) return null;
    final uri = Uri.parse('$baseUrl/detect');
    try {
      final res = await _http
          .post(
            uri,
            headers: const {'content-type': 'application/octet-stream'},
            body: photoBytes,
          )
          .timeout(timeout);
      if (res.statusCode != 200) {
        stderr.writeln(
            'face-mesh /detect ${res.statusCode}: ${res.body}');
        return null;
      }
      final j = jsonDecode(res.body);
      if (j is! Map) return null;
      if (j['found'] != true) return null;
      final out = j.cast<String, dynamic>();
      if (out['bbox'] is! List ||
          out['landmarks'] is! Map ||
          out['contour'] is! List) {
        return null;
      }
      return out;
    } on TimeoutException {
      stderr.writeln('face-mesh /detect timed out after $timeout');
      return null;
    } catch (e) {
      stderr.writeln('face-mesh /detect failed: $e');
      return null;
    }
  }

  Future<bool> health() async {
    if (!configured) return false;
    try {
      final res = await _http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void close() => _http.close();
}
