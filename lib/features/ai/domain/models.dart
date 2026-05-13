import 'dart:convert';

class SkinProfile {
  const SkinProfile({
    this.name,
    this.gender,
    this.skinType,
    this.pores,
    this.concerns = const [],
    this.acneType,
    this.sensitivity,
    this.sensitivityReaction,
    this.budget,
    this.extras = const {},
  });

  final String? name;

  /// 'female' | 'male' | null. Drives gendered phrasing throughout the app.
  /// Null is treated as unknown — phrasing falls back to gender-neutral.
  final String? gender;

  final String? skinType;
  final String? pores;
  final List<String> concerns;
  final String? acneType;
  final String? sensitivity;
  final String? sensitivityReaction;
  final String? budget;
  final Map<String, String> extras;

  bool get isMale => gender == 'male';
  bool get isFemale => gender == 'female';

  SkinProfile copyWith({
    String? name,
    String? gender,
    String? skinType,
    String? pores,
    List<String>? concerns,
    String? acneType,
    String? sensitivity,
    String? sensitivityReaction,
    String? budget,
    Map<String, String>? extras,
  }) {
    return SkinProfile(
      name: name ?? this.name,
      gender: gender ?? this.gender,
      skinType: skinType ?? this.skinType,
      pores: pores ?? this.pores,
      concerns: concerns ?? this.concerns,
      acneType: acneType ?? this.acneType,
      sensitivity: sensitivity ?? this.sensitivity,
      sensitivityReaction: sensitivityReaction ?? this.sensitivityReaction,
      budget: budget ?? this.budget,
      extras: extras ?? this.extras,
    );
  }

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (gender != null) 'gender': gender,
        if (skinType != null) 'skin_type': skinType,
        if (pores != null) 'pores': pores,
        if (concerns.isNotEmpty) 'concerns': concerns,
        if (acneType != null) 'acne_type': acneType,
        if (sensitivity != null) 'sensitivity': sensitivity,
        if (sensitivityReaction != null)
          'sensitivity_reaction': sensitivityReaction,
        if (budget != null) 'budget': budget,
        if (extras.isNotEmpty) 'extras': extras,
      };

  bool get hasMinimumData =>
      skinType != null && concerns.isNotEmpty && budget != null;
}

class RoutineStep {
  const RoutineStep({
    required this.title,
    required this.ingredients,
    required this.explanation,
  });

  final String title;
  final List<String> ingredients;
  final String explanation;

  factory RoutineStep.fromJson(Map<String, dynamic> j) => RoutineStep(
        title: j['title'] as String? ?? j['step'] as String? ?? '',
        ingredients: (j['ingredients'] as List?)?.cast<String>() ?? const [],
        explanation: j['explanation'] as String? ?? '',
      );
}

class RoutineResult {
  const RoutineResult({
    required this.morning,
    required this.evening,
    required this.warnings,
    required this.tips,
    this.skinSummary,
    this.skinScore,
    this.confidence,
  });

  final List<RoutineStep> morning;
  final List<RoutineStep> evening;
  final List<String> warnings;
  final List<String> tips;
  final String? skinSummary;
  final int? skinScore;
  final double? confidence;

  factory RoutineResult.fromJson(Map<String, dynamic> j) {
    final analysis = j['analysis'] as Map<String, dynamic>?;
    List<RoutineStep> parseSteps(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) {
        if (e is Map<String, dynamic>) return RoutineStep.fromJson(e);
        if (e is String) {
          return RoutineStep(
              title: e, ingredients: const [], explanation: '');
        }
        return const RoutineStep(
            title: '', ingredients: [], explanation: '');
      }).toList();
    }

    return RoutineResult(
      morning: parseSteps(j['morning_routine'] ?? j['morning']),
      evening: parseSteps(j['evening_routine'] ?? j['evening']),
      warnings: (j['warnings'] as List?)?.cast<String>() ?? const [],
      tips: (j['tips'] as List?)?.cast<String>() ?? const [],
      skinSummary: analysis?['skin_summary'] as String? ??
          j['skin_summary'] as String?,
      skinScore: (analysis?['skin_score'] as num?)?.toInt() ??
          (j['skin_score'] as num?)?.toInt(),
      confidence: (analysis?['confidence'] as num?)?.toDouble() ??
          (j['confidence'] as num?)?.toDouble(),
    );
  }
}

/// Discriminated response from Dermatologist 2.0 prompt.
sealed class DermResponse {
  const DermResponse();

  static DermResponse parse(String raw) {
    final cleaned = _stripCodeFence(raw);
    final j = jsonDecode(cleaned) as Map<String, dynamic>;
    final followUp = j['follow_up_question'];
    final confidence = (j['confidence'] as num?)?.toDouble() ??
        ((j['analysis'] as Map?)?['confidence'] as num?)?.toDouble() ??
        0.0;

    final hasRoutine =
        (j['morning_routine'] is List) || (j['evening_routine'] is List);

    if (followUp is String && followUp.trim().isNotEmpty && !hasRoutine) {
      return DermClarification(
        question: followUp,
        confidence: confidence,
      );
    }
    return DermReady(
      confidence: confidence,
      result: RoutineResult.fromJson(j),
    );
  }

  static String _stripCodeFence(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    }
    return s.trim();
  }
}

class DermClarification extends DermResponse {
  const DermClarification({required this.question, required this.confidence});
  final String question;
  final double confidence;
}

class DermReady extends DermResponse {
  const DermReady({required this.confidence, required this.result});
  final double confidence;
  final RoutineResult result;
}
