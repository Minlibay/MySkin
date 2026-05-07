import 'models.dart';

abstract class AIService {
  /// Standard one-shot routine generation.
  Future<RoutineResult> generateRoutine(SkinProfile profile);

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
