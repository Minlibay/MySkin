import 'dart:convert';

import '../../catalog/domain/product.dart';

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

  /// Budget was once required here, but the onboarding step that captured it
  /// has been removed — gating the rest of the app on a question we no longer
  /// ask would lock out every newly onboarded user.
  bool get hasMinimumData =>
      skinType != null && concerns.isNotEmpty;
}

class RoutineStep {
  const RoutineStep({
    required this.title,
    required this.ingredients,
    required this.explanation,
    this.kind,
    this.product,
    this.recommendation,
  });

  final String title;
  final List<String> ingredients;
  final String explanation;

  /// Canonical product `kind` the backend inferred for this step
  /// (cleanser/serum/moisturizer/…). Null when the title didn't match.
  final String? kind;

  /// Concrete product from the user's shelf that fulfils this step.
  final Product? product;

  /// Personalised top-1 catalog match for this kind, sent only when the
  /// shelf doesn't already cover this step. Drives the "Купить" CTA.
  final Product? recommendation;

  factory RoutineStep.fromJson(Map<String, dynamic> j) {
    Product? parseProd(dynamic v) {
      if (v is! Map<String, dynamic>) return null;
      try {
        return Product.fromJson(v);
      } catch (_) {
        return null;
      }
    }

    return RoutineStep(
      title: j['title'] as String? ?? j['step'] as String? ?? '',
      ingredients: (j['ingredients'] as List?)?.cast<String>() ?? const [],
      explanation: j['explanation'] as String? ?? '',
      kind: j['kind'] as String?,
      product: parseProd(j['product']),
      recommendation: parseProd(j['recommendation']),
    );
  }
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
