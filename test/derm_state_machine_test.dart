import 'package:flutter_test/flutter_test.dart';
import 'package:myskin/features/ai/domain/ai_service.dart';
import 'package:myskin/features/ai/domain/models.dart';
import 'package:myskin/features/derm2/domain/derm_state.dart';
import 'package:myskin/features/derm2/presentation/derm_state_machine_controller.dart';

class _ScriptedAI implements AIService {
  _ScriptedAI(this.responses);
  final List<DermResponse> responses;
  int _i = 0;

  @override
  Future<DermResponse> dermAnalyze({
    required SkinProfile profile,
    required List<DermTurn> history,
  }) async {
    return responses[_i++];
  }

  @override
  Future<RoutineResult> generateRoutine(SkinProfile profile) async {
    return const RoutineResult(
      morning: [],
      evening: [],
      warnings: [],
      tips: [],
      confidence: 0.9,
    );
  }
}

void main() {
  const profile = SkinProfile(
    skinType: 'dry',
    concerns: ['dehydration'],
    sensitivity: 'no',
    budget: 'mid',
  );

  test('low confidence → NEED_CLARIFICATION', () async {
    final ai = _ScriptedAI([
      const DermClarification(
          question: 'Стянутость к вечеру?', confidence: 0.5),
    ]);
    final ctrl = DermStateMachineController(ai);
    await ctrl.start(profile);
    expect(ctrl.state.phase, DermPhase.needClarification);
    expect(ctrl.state.pendingQuestion, isNotNull);
  });

  test('high confidence → SHOW_RESULT', () async {
    final ai = _ScriptedAI([
      const DermReady(
        confidence: 0.92,
        result: RoutineResult(
          morning: [],
          evening: [],
          warnings: [],
          tips: [],
          confidence: 0.92,
        ),
      ),
    ]);
    final ctrl = DermStateMachineController(ai);
    await ctrl.start(profile);
    expect(ctrl.state.phase, DermPhase.showResult);
    expect(ctrl.state.result, isNotNull);
  });

  test('clarification answer loops back through ANALYZING', () async {
    final ai = _ScriptedAI([
      const DermClarification(question: 'Q1?', confidence: 0.5),
      const DermReady(
        confidence: 0.9,
        result: RoutineResult(
            morning: [], evening: [], warnings: [], tips: []),
      ),
    ]);
    final ctrl = DermStateMachineController(ai);
    await ctrl.start(profile);
    expect(ctrl.state.phase, DermPhase.needClarification);
    await ctrl.submitClarification('к вечеру');
    expect(ctrl.state.phase, DermPhase.showResult);
    expect(ctrl.state.history, hasLength(1));
    expect(ctrl.state.history.first.answer, 'к вечеру');
  });

  test('safety: too many loops force a routine', () async {
    final ai = _ScriptedAI(List.generate(
        10,
        (_) => const DermClarification(
            question: 'Q?', confidence: 0.5)));
    final ctrl = DermStateMachineController(ai);
    await ctrl.start(profile);
    for (var i = 0; i < 6; i++) {
      if (ctrl.state.phase == DermPhase.needClarification) {
        await ctrl.submitClarification('a');
      }
    }
    expect(ctrl.state.phase, DermPhase.showResult);
  });
}
