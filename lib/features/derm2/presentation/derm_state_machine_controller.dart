import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ai/domain/ai_service.dart';
import '../../ai/domain/models.dart';
import '../../api/backend_api.dart';
import '../domain/derm_state.dart';

/// State machine driving Dermatologist 2.0 mode.
///
/// Transitions:
///   INIT → COLLECTING_DATA → ANALYZING
///   ANALYZING → NEED_CLARIFICATION (confidence < threshold)
///   ANALYZING → READY_TO_RECOMMEND (confidence >= threshold)
///   NEED_CLARIFICATION → COLLECTING_CLARIFICATION → ANALYZING
///   READY_TO_RECOMMEND → GENERATING_ROUTINE → SHOW_RESULT
///   SHOW_RESULT → FOLLOW_UP → ANALYZING (loop)
class DermStateMachineController extends StateNotifier<DermState> {
  DermStateMachineController(this._ai, {this.onCompleted})
      : super(const DermState());

  final AIService _ai;

  /// Fired once when SHOW_RESULT is reached. Used to persist to backend.
  final void Function(DermState finalState)? onCompleted;

  static const double confidenceThreshold = 0.85;
  static const int maxClarificationLoops = 4;

  /// Begin a new session with onboarding-collected profile.
  Future<void> start(SkinProfile profile) async {
    _transition(DermPhase.init);
    state = state.copyWith(
      profile: profile,
      history: const [],
      clearQuestion: true,
      clearError: true,
      result: null,
    );
    _transition(DermPhase.collectingData);
    await _runAnalysis();
  }

  /// User answered the pending clarifying question.
  Future<void> submitClarification(String answer) async {
    final question = state.pendingQuestion;
    if (question == null || state.phase != DermPhase.needClarification) {
      return;
    }
    _transition(DermPhase.collectingClarification);
    final updatedHistory = [
      ...state.history,
      DermTurn(question: question, answer: answer),
    ];
    state = state.copyWith(
      history: updatedHistory,
      profile: state.profile.copyWith(extras: {
        ...state.profile.extras,
        'clarification_${updatedHistory.length}': answer,
      }),
      clearQuestion: true,
    );
    await _runAnalysis();
  }

  /// User in SHOW_RESULT phase reports a change → re-enter loop.
  Future<void> submitFollowUp(String message) async {
    if (state.phase != DermPhase.showResult &&
        state.phase != DermPhase.followUp) {
      return;
    }
    _transition(DermPhase.followUp);
    final updatedHistory = [
      ...state.history,
      DermTurn(question: '[follow-up]', answer: message),
    ];
    state = state.copyWith(
      history: updatedHistory,
      profile: state.profile.copyWith(extras: {
        ...state.profile.extras,
        'follow_up_${updatedHistory.length}': message,
      }),
      result: null,
    );
    await _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    if (state.history.length > maxClarificationLoops) {
      // Safety: force a recommendation if we've looped too many times.
      await _generateRoutine(forced: true);
      return;
    }
    _transition(DermPhase.analyzing);
    try {
      final response = await _ai.dermAnalyze(
        profile: state.profile,
        history: state.history,
      );
      switch (response) {
        case DermClarification(:final question, :final confidence):
          if (confidence >= confidenceThreshold) {
            // AI hedged but is confident — push forward.
            await _generateRoutine();
            return;
          }
          state = state.copyWith(
            pendingQuestion: question,
            confidence: confidence,
          );
          _transition(DermPhase.needClarification);
        case DermReady(:final confidence, :final result):
          state = state.copyWith(confidence: confidence, result: result);
          _transition(DermPhase.readyToRecommend);
          // Result already includes the routine in this prompt design.
          _transition(DermPhase.generatingRoutine);
          _transition(DermPhase.showResult);
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Не удалось получить ответ AI: $e',
      );
      _transition(DermPhase.error);
    }
  }

  Future<void> _generateRoutine({bool forced = false}) async {
    _transition(DermPhase.readyToRecommend);
    _transition(DermPhase.generatingRoutine);
    try {
      final result = await _ai.generateRoutine(state.profile);
      state = state.copyWith(
        result: result,
        confidence: forced ? 0.85 : state.confidence,
      );
      _transition(DermPhase.showResult);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Ошибка генерации: $e');
      _transition(DermPhase.error);
    }
  }

  void reset() {
    state = const DermState();
  }

  void _transition(DermPhase next) {
    final wasShowing = state.phase == DermPhase.showResult;
    state = state.copyWith(phase: next, clearError: next != DermPhase.error);
    if (next == DermPhase.showResult && !wasShowing) {
      onCompleted?.call(state);
    }
  }
}

/// Inject the AIService implementation here (Mock or GigaChat).
final aiServiceProvider = Provider<AIService>((ref) {
  throw UnimplementedError(
      'Override aiServiceProvider in main.dart with MockAIService or GigachatService');
});

final dermControllerProvider = StateNotifierProvider.autoDispose<
    DermStateMachineController, DermState>((ref) {
  final api = ref.watch(backendApiProvider);
  return DermStateMachineController(
    ref.watch(aiServiceProvider),
    onCompleted: (s) async {
      final result = s.result;
      if (result == null) return;
      // Don't persist empty recommendations — they pollute /me/today and
      // make the ritual screen render a stub with no steps.
      if (result.morning.isEmpty && result.evening.isEmpty) return;
      try {
        await api.saveDermSession(
          profile: s.profile,
          history: s.history.map((t) => t.toJson()).toList(),
          finalPhase: s.phase.name,
          confidence: s.confidence,
        );
        await api.saveRoutine(kind: 'derm2', result: result);
      } catch (_) {
        // best-effort
      }
    },
  );
});
