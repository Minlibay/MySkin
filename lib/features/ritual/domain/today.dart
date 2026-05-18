import '../../catalog/domain/product.dart';

/// "Today" payload returned by GET /me/today — list of morning/evening steps
/// with completion booleans + streak counter.
class TodayStep {
  const TodayStep({
    required this.index,
    required this.title,
    required this.ingredients,
    required this.explanation,
    required this.done,
  });

  final int index;
  final String title;
  final List<String> ingredients;
  final String explanation;
  final bool done;

  TodayStep copyWith({bool? done}) => TodayStep(
        index: index,
        title: title,
        ingredients: ingredients,
        explanation: explanation,
        done: done ?? this.done,
      );

  factory TodayStep.fromJson(Map<String, dynamic> j) => TodayStep(
        index: (j['index'] as num).toInt(),
        title: j['title'] as String? ?? '',
        ingredients:
            ((j['ingredients'] as List?) ?? const []).cast<String>(),
        explanation: j['explanation'] as String? ?? '',
        done: j['done'] as bool? ?? false,
      );
}

class Today {
  const Today({
    required this.streak,
    required this.hasRoutine,
    required this.morning,
    required this.evening,
    this.shelfMorning = const [],
    this.shelfEvening = const [],
    this.tip,
  });

  final int streak;
  final bool hasRoutine;
  final List<TodayStep> morning;
  final List<TodayStep> evening;

  /// Products from the user's shelf, grouped by phase. The Ritual screen
  /// renders these under the morning / evening tabs so the user sees what
  /// they actually own — not just generic step titles.
  final List<Product> shelfMorning;
  final List<Product> shelfEvening;

  /// Optional Лина tip surfaced by the backend (currently the latest scan's
  /// `insight`). Null when there's no scan yet — the UI then falls back to
  /// its own rotating advice.
  final String? tip;

  int get morningDone => morning.where((s) => s.done).length;
  int get eveningDone => evening.where((s) => s.done).length;
  bool get allDone =>
      morning.isNotEmpty &&
      evening.isNotEmpty &&
      morning.every((s) => s.done) &&
      evening.every((s) => s.done);

  factory Today.fromJson(Map<String, dynamic> j) {
    List<TodayStep> parse(dynamic v) {
      if (v is! List) return const [];
      return v
          .cast<Map<String, dynamic>>()
          .map(TodayStep.fromJson)
          .toList();
    }

    List<Product> parseProducts(dynamic v) {
      if (v is! List) return const [];
      final out = <Product>[];
      for (final raw in v) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          out.add(Product.fromJson(raw));
        } catch (_) {
          // Skip malformed entries rather than crash the Ritual screen.
        }
      }
      return out;
    }

    return Today(
      streak: (j['streak'] as num?)?.toInt() ?? 0,
      hasRoutine: j['has_routine'] as bool? ?? false,
      morning: parse(j['morning']),
      evening: parse(j['evening']),
      shelfMorning: parseProducts(j['shelf_morning']),
      shelfEvening: parseProducts(j['shelf_evening']),
      tip: j['tip'] as String?,
    );
  }

  Today withToggled(String phase, int index) {
    if (phase == 'morning') {
      return Today(
        streak: streak,
        hasRoutine: hasRoutine,
        morning: [
          for (final s in morning)
            s.index == index ? s.copyWith(done: !s.done) : s
        ],
        evening: evening,
        shelfMorning: shelfMorning,
        shelfEvening: shelfEvening,
        tip: tip,
      );
    }
    return Today(
      streak: streak,
      hasRoutine: hasRoutine,
      morning: morning,
      evening: [
        for (final s in evening)
          s.index == index ? s.copyWith(done: !s.done) : s
      ],
      shelfMorning: shelfMorning,
      shelfEvening: shelfEvening,
      tip: tip,
    );
  }
}
