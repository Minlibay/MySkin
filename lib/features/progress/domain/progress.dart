class ProgressPoint {
  const ProgressPoint({
    required this.id,
    required this.date,
    required this.score,
    required this.hydration,
    required this.sebum,
    required this.tone,
    required this.pores,
    required this.hasPhoto,
  });

  final String id;
  final DateTime date;
  final int score;
  final int hydration;
  final int sebum;
  final int tone;
  final int pores;
  final bool hasPhoto;

  factory ProgressPoint.fromJson(Map<String, dynamic> j) => ProgressPoint(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        score: (j['score'] as num).toInt(),
        hydration: (j['hydration'] as num).toInt(),
        sebum: (j['sebum'] as num).toInt(),
        tone: (j['tone'] as num).toInt(),
        pores: (j['pores'] as num).toInt(),
        hasPhoto: j['has_photo'] as bool? ?? false,
      );
}

class ProgressStats {
  const ProgressStats({
    required this.scansTotal,
    required this.scansInWindow,
    required this.completionStreak,
    this.latestScore,
    this.firstScore,
  });

  final int scansTotal;
  final int scansInWindow;
  final int completionStreak;
  final int? latestScore;
  final int? firstScore;

  int? get delta => (latestScore != null && firstScore != null)
      ? latestScore! - firstScore!
      : null;

  factory ProgressStats.fromJson(Map<String, dynamic> j) => ProgressStats(
        scansTotal: (j['scans_total'] as num?)?.toInt() ?? 0,
        scansInWindow: (j['scans_in_window'] as num?)?.toInt() ?? 0,
        completionStreak:
            (j['completion_streak'] as num?)?.toInt() ?? 0,
        latestScore: (j['latest_score'] as num?)?.toInt(),
        firstScore: (j['first_score'] as num?)?.toInt(),
      );
}

class ProgressData {
  const ProgressData({
    required this.days,
    required this.points,
    required this.stats,
  });

  final int days;
  final List<ProgressPoint> points;
  final ProgressStats stats;

  factory ProgressData.fromJson(Map<String, dynamic> j) => ProgressData(
        days: (j['days'] as num?)?.toInt() ?? 30,
        points: ((j['points'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ProgressPoint.fromJson)
            .toList(),
        stats: ProgressStats.fromJson(
            (j['stats'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}
