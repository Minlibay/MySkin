import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ai/domain/models.dart';
import '../domain/onboarding_step.dart';

class OnboardingState {
  const OnboardingState({
    this.profile = const SkinProfile(),
    this.currentStep = OnboardingStepId.name,
    this.history = const [OnboardingStepId.name],
  });

  final SkinProfile profile;
  final OnboardingStepId currentStep;
  final List<OnboardingStepId> history;

  bool get isDone => currentStep == OnboardingStepId.done;

  /// Approximate progress for the progress bar. The branch length varies,
  /// so this is intentionally heuristic — feels better than jumping.
  double get progress {
    const total = 6.0;
    return (history.length / total).clamp(0.0, 1.0);
  }

  OnboardingState copyWith({
    SkinProfile? profile,
    OnboardingStepId? currentStep,
    List<OnboardingStepId>? history,
  }) =>
      OnboardingState(
        profile: profile ?? this.profile,
        currentStep: currentStep ?? this.currentStep,
        history: history ?? this.history,
      );
}

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController() : super(const OnboardingState());

  void selectSingle(String value) {
    final updated = _applyAnswer(state.profile, state.currentStep, [value]);
    final next = OnboardingFlow.next(updated, state.currentStep);
    state = state.copyWith(
      profile: updated,
      currentStep: next,
      history: [...state.history, next],
    );
  }

  void toggleMulti(String value) {
    final current = state.profile.concerns;
    final updated = current.contains(value)
        ? current.where((v) => v != value).toList()
        : [...current, value];
    state = state.copyWith(
      profile: state.profile.copyWith(concerns: updated),
    );
  }

  /// Confirm a multi-select step (concerns).
  void confirmMulti() {
    if (state.currentStep != OnboardingStepId.concerns) return;
    if (state.profile.concerns.isEmpty) return;
    final next = OnboardingFlow.next(state.profile, state.currentStep);
    state = state.copyWith(
      currentStep: next,
      history: [...state.history, next],
    );
  }

  /// Submit a free-text answer (e.g. name).
  void submitText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final updated = state.profile.copyWith(
      name: state.currentStep == OnboardingStepId.name ? trimmed : state.profile.name,
    );
    final next = OnboardingFlow.next(updated, state.currentStep);
    state = state.copyWith(
      profile: updated,
      currentStep: next,
      history: [...state.history, next],
    );
  }

  void back() {
    if (state.history.length <= 1) return;
    final newHistory = [...state.history]..removeLast();
    state = state.copyWith(
      currentStep: newHistory.last,
      history: newHistory,
    );
  }

  SkinProfile _applyAnswer(
      SkinProfile profile, OnboardingStepId step, List<String> values) {
    final v = values.first;
    switch (step) {
      case OnboardingStepId.gender:
        return profile.copyWith(gender: v);
      case OnboardingStepId.skinType:
        return profile.copyWith(skinType: v);
      case OnboardingStepId.skinTypeHelp:
        return profile.copyWith(skinType: v);
      case OnboardingStepId.pores:
        return profile.copyWith(pores: v);
      case OnboardingStepId.acneType:
        return profile.copyWith(acneType: v);
      case OnboardingStepId.sensitivity:
        return profile.copyWith(sensitivity: v);
      case OnboardingStepId.sensitivityReaction:
        return profile.copyWith(sensitivityReaction: v);
      case OnboardingStepId.budget:
        return profile.copyWith(budget: v);
      case OnboardingStepId.name:
      case OnboardingStepId.concerns:
      case OnboardingStepId.done:
        return profile;
    }
  }
}

final onboardingControllerProvider =
    StateNotifierProvider.autoDispose<OnboardingController, OnboardingState>(
  (ref) => OnboardingController(),
);
