/// Skin analysis returned by POST /me/scans and GET /me/scans/:id.
class ScanResult {
  const ScanResult({
    required this.id,
    required this.score,
    required this.hydration,
    required this.sebum,
    required this.tone,
    required this.pores,
    required this.zones,
    required this.insight,
    required this.createdAt,
    required this.hasPhoto,
    this.qualityWarnings = const [],
    this.meta = const {},
    this.face,
  });

  final String id;
  final int score;
  final int hydration;
  final int sebum;
  final int tone;
  final int pores;
  final ScanZones zones;
  final String insight;
  final DateTime createdAt;
  final bool hasPhoto;
  final List<String> qualityWarnings;
  final Map<String, dynamic> meta;
  /// Where the face sits on the source photo (normalised 0..1). Null
  /// for old scans, fallback runs without a photo, or when skin detection
  /// failed.
  final FaceGeometry? face;

  /// Friendly Russian translations for known quality flags.
  Iterable<String> get qualityMessages sync* {
    for (final w in qualityWarnings) {
      yield switch (w) {
        'image_too_dark' => 'Слишком темно — повтори при дневном свете.',
        'image_overexposed' =>
          'Засвет — отвернись от прямого источника света.',
        'image_too_small' =>
          'Фото слишком маленькое — используй камеру в полном размере.',
        'no_face_detected' =>
          'Лицо не найдено — займи 2/3 кадра, поверни анфас.',
        'no_photo' => 'Скан без фото — анализ по профилю.',
        'cannot_decode' => 'Не удалось прочитать фото. Попробуй другое.',
        _ => 'Качество фото может влиять на точность.',
      };
    }
  }

  bool get hasQualityIssues => qualityWarnings.isNotEmpty;

  factory ScanResult.fromJson(Map<String, dynamic> j) {
    return ScanResult(
      id: j['id'] as String,
      score: (j['score'] as num).toInt(),
      hydration: (j['hydration'] as num).toInt(),
      sebum: (j['sebum'] as num).toInt(),
      tone: (j['tone'] as num).toInt(),
      pores: (j['pores'] as num).toInt(),
      zones: ScanZones.fromJson(
          (j['zones'] as Map?)?.cast<String, dynamic>() ?? const {}),
      insight: j['insight'] as String? ?? '',
      createdAt: DateTime.parse(j['created_at'] as String),
      hasPhoto: j['has_photo'] as bool? ?? false,
      qualityWarnings:
          ((j['quality_warnings'] as List?) ?? const []).cast<String>(),
      meta:
          (j['analysis_meta'] as Map?)?.cast<String, dynamic>() ?? const {},
      face: FaceGeometry.tryFromJson(j['face']),
    );
  }
}

/// Geometry of the user's face on the saved scan photo. Everything is in
/// normalised image coordinates (0..1). Produced by `buildFaceGeomJson`
/// on the mobile client at scan time and stored verbatim on the backend
/// — the result screen never re-detects.
class FaceGeometry {
  const FaceGeometry({
    required this.bbox,
    this.contour,
    this.landmarks,
  });

  /// `[x0, y0, x1, y1]` ML Kit bounding box.
  final List<double> bbox;

  /// Face outline polygon. Null when ML Kit didn't return contours
  /// (older devices, fast-mode fallback, …) — renderer falls back to a
  /// synthesised ellipse from the bbox.
  final List<List<double>>? contour;

  /// Zone landmark points, keyed by zone id: `forehead`, `tzone`,
  /// `left_cheek`, `right_cheek`, `chin`. Null when contour is null.
  final Map<String, List<double>>? landmarks;

  double get x0 => bbox[0];
  double get y0 => bbox[1];
  double get x1 => bbox[2];
  double get y1 => bbox[3];
  double get width => x1 - x0;
  double get height => y1 - y0;

  static FaceGeometry? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final raw = j['bbox'];
    if (raw is! List || raw.length != 4) return null;
    final bbox = raw
        .whereType<num>()
        .map((n) => n.toDouble().clamp(0.0, 1.0))
        .toList();
    if (bbox.length != 4) return null;
    if (bbox[2] <= bbox[0] || bbox[3] <= bbox[1]) return null;

    List<List<double>>? contour;
    final rawC = j['contour'];
    if (rawC is List && rawC.length >= 8) {
      final out = <List<double>>[];
      for (final p in rawC) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          out.add([
            (p[0] as num).toDouble().clamp(0.0, 1.0),
            (p[1] as num).toDouble().clamp(0.0, 1.0),
          ]);
        }
      }
      if (out.length >= 8) contour = out;
    }

    Map<String, List<double>>? landmarks;
    final rawL = j['landmarks'];
    if (rawL is Map) {
      final out = <String, List<double>>{};
      for (final key in const [
        'forehead',
        'tzone',
        'left_cheek',
        'right_cheek',
        'chin'
      ]) {
        final v = rawL[key];
        if (v is List && v.length >= 2 && v[0] is num && v[1] is num) {
          out[key] = [
            (v[0] as num).toDouble().clamp(0.0, 1.0),
            (v[1] as num).toDouble().clamp(0.0, 1.0),
          ];
        }
      }
      if (out.length == 5) landmarks = out;
    }

    return FaceGeometry(bbox: bbox, contour: contour, landmarks: landmarks);
  }
}

/// Лина's drill-down for a single face zone of a scan. Used to back the
/// bottom-sheet that opens when the user taps a zone on the heatmap.
class ZoneInsight {
  const ZoneInsight({
    required this.zone,
    required this.score,
    required this.issue,
    required this.remedies,
    required this.concern,
  });

  /// Backend zone key: forehead | tzone | left_cheek | right_cheek | chin.
  final String zone;
  final int score;
  final String issue;
  final List<String> remedies;

  /// Catalog filter key (acne, dehydration, etc.) so the "Подобрать средства"
  /// CTA can open the catalog pre-filtered. Empty when the zone is fine and
  /// no specific concern applies.
  final String concern;

  factory ZoneInsight.fromJson(Map<String, dynamic> j) => ZoneInsight(
        zone: j['zone'] as String? ?? '',
        score: (j['score'] as num?)?.toInt() ?? 0,
        issue: j['issue'] as String? ?? '',
        remedies:
            ((j['remedies'] as List?) ?? const []).map((e) => '$e').toList(),
        concern: j['concern'] as String? ?? '',
      );
}

class ScanZones {
  const ScanZones({
    required this.forehead,
    required this.tzone,
    required this.cheeks,
    required this.chin,
  });

  final int forehead;
  final int tzone;
  final int cheeks;
  final int chin;

  factory ScanZones.fromJson(Map<String, dynamic> j) => ScanZones(
        forehead: (j['forehead'] as num?)?.toInt() ?? 70,
        tzone: (j['tzone'] as num?)?.toInt() ?? 70,
        cheeks: (j['cheeks'] as num?)?.toInt() ?? 70,
        chin: (j['chin'] as num?)?.toInt() ?? 70,
      );
}
