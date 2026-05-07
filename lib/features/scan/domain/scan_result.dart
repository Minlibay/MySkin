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
    );
  }
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
