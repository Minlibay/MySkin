import '../../ai/domain/ai_service.dart';
import '../../ai/domain/models.dart';

/// Discrete states for the Dermatologist 2.0 conversation flow.
enum DermPhase {
  init,
  collectingData,
  analyzing,
  needClarification,
  collectingClarification,
  readyToRecommend,
  generatingRoutine,
  showResult,
  followUp,
  error,
}

class DermState {
  const DermState({
    this.phase = DermPhase.init,
    this.profile = const SkinProfile(),
    this.history = const [],
    this.pendingQuestion,
    this.confidence,
    this.result,
    this.errorMessage,
  });

  final DermPhase phase;
  final SkinProfile profile;
  final List<DermTurn> history;
  final String? pendingQuestion;
  final double? confidence;
  final RoutineResult? result;
  final String? errorMessage;

  bool get isBusy =>
      phase == DermPhase.analyzing || phase == DermPhase.generatingRoutine;

  DermState copyWith({
    DermPhase? phase,
    SkinProfile? profile,
    List<DermTurn>? history,
    String? pendingQuestion,
    double? confidence,
    RoutineResult? result,
    String? errorMessage,
    bool clearQuestion = false,
    bool clearError = false,
  }) {
    return DermState(
      phase: phase ?? this.phase,
      profile: profile ?? this.profile,
      history: history ?? this.history,
      pendingQuestion:
          clearQuestion ? null : (pendingQuestion ?? this.pendingQuestion),
      confidence: confidence ?? this.confidence,
      result: result ?? this.result,
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
