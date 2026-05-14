import 'models.dart';

abstract class AIService {
  /// Standard one-shot routine generation. Optional [checkIn] is a same-day
  /// snapshot from the quick check-in flow (mood / today's notice / today's
  /// focus) — the backend folds it into the prompt so the resulting routine
  /// reflects how the skin feels *right now*, not just the static profile.
  Future<RoutineResult> generateRoutine(SkinProfile profile,
      {Map<String, String>? checkIn});

  /// Dermatologist 2.0 — may return either a clarifying question
  /// or a ready routine based on confidence.
  Future<DermResponse> dermAnalyze({
    required SkinProfile profile,
    required List<DermTurn> history,
  });
}

class DermTurn {
  const DermTurn({required this.question, required this.answer});
  final String question;
  final String answer;

  Map<String, dynamic> toJson() =>
      {'question': question, 'answer': answer};
}
