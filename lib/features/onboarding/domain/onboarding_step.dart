import '../../ai/domain/models.dart';

enum OnboardingStepId {
  name,
  gender,
  skinType,
  skinTypeHelp,
  pores,
  concerns,
  acneType,
  sensitivity,
  sensitivityReaction,
  done,
}

class StepOption {
  const StepOption({
    required this.id,
    required this.title,
    this.subtitle,
    this.emoji,
  });
  final String id;
  final String title;
  final String? subtitle;
  final String? emoji;
}

class OnboardingStep {
  const OnboardingStep({
    required this.id,
    required this.title,
    this.subtitle,
    this.options = const [],
    this.multiSelect = false,
    this.isTextInput = false,
    this.placeholder,
  });

  final OnboardingStepId id;
  final String title;
  final String? subtitle;
  final List<StepOption> options;
  final bool multiSelect;
  final bool isTextInput;
  final String? placeholder;
}

/// Branching logic — decides the next step based on the running profile
/// and the most recent user input. Keeps presentation clean and testable.
class OnboardingFlow {
  static const nameStep = OnboardingStep(
    id: OnboardingStepId.name,
    title: 'Как тебя зовут?',
    subtitle: 'Будем обращаться по имени',
    isTextInput: true,
    placeholder: 'Имя',
  );

  static const genderStep = OnboardingStep(
    id: OnboardingStepId.gender,
    title: 'Чтобы правильно обращаться',
    subtitle: 'Влияет только на формулировки в приложении',
    options: [
      StepOption(id: 'female', title: 'Я девушка', emoji: '🌸'),
      StepOption(id: 'male', title: 'Я парень', emoji: '🌿'),
    ],
  );

  static const skinTypeStep = OnboardingStep(
    id: OnboardingStepId.skinType,
    title: 'Какой у тебя тип кожи?',
    subtitle: 'Выбери, как ощущаешь её обычно',
    options: [
      StepOption(id: 'dry', title: 'Сухая', subtitle: 'Стянутость, шелушения', emoji: '🌵'),
      StepOption(id: 'oily', title: 'Жирная', subtitle: 'Блеск, расширенные поры', emoji: '🫧'),
      StepOption(id: 'combo', title: 'Комбинированная', subtitle: 'Жирная Т-зона', emoji: '🪞'),
      StepOption(id: 'normal', title: 'Нормальная', subtitle: 'Без выраженных проблем', emoji: '🌸'),
      StepOption(id: 'unknown', title: 'Не знаю', subtitle: 'Помоги определить', emoji: '🤔'),
    ],
  );

  static const skinTypeHelpStep = OnboardingStep(
    id: OnboardingStepId.skinTypeHelp,
    title: 'Через 1 час после умывания кожа…',
    options: [
      StepOption(id: 'dry', title: 'Стянута, ощущается сухой', emoji: '🌵'),
      StepOption(id: 'normal', title: 'Комфортная, ровная', emoji: '🌸'),
      StepOption(id: 'combo', title: 'Жирная только в Т-зоне', emoji: '🪞'),
      StepOption(id: 'oily', title: 'Блестит везде', emoji: '🫧'),
    ],
  );

  static const poresStep = OnboardingStep(
    id: OnboardingStepId.pores,
    title: 'Как насчёт пор?',
    options: [
      StepOption(id: 'small', title: 'Незаметные', emoji: '✨'),
      StepOption(id: 'medium', title: 'Заметны в Т-зоне', emoji: '🔍'),
      StepOption(id: 'large', title: 'Расширенные', emoji: '🕳️'),
    ],
  );

  static const concernsStep = OnboardingStep(
    id: OnboardingStepId.concerns,
    title: 'Что хочется улучшить?',
    subtitle: 'Можно выбрать несколько',
    multiSelect: true,
    options: [
      StepOption(id: 'acne', title: 'Акне / прыщи'),
      StepOption(id: 'pih', title: 'Пост-акне, пятна'),
      StepOption(id: 'aging', title: 'Морщины, упругость'),
      StepOption(id: 'dullness', title: 'Тусклый цвет'),
      StepOption(id: 'redness', title: 'Покраснения'),
      StepOption(id: 'dehydration', title: 'Обезвоженность'),
    ],
  );

  static const acneTypeStep = OnboardingStep(
    id: OnboardingStepId.acneType,
    title: 'Какие высыпания чаще?',
    options: [
      StepOption(id: 'comedones', title: 'Чёрные точки, забитые поры', emoji: '⚫'),
      StepOption(id: 'inflammatory', title: 'Воспалённые прыщи', emoji: '🔴'),
      StepOption(id: 'mixed', title: 'И то и другое', emoji: '🌗'),
      StepOption(id: 'hormonal', title: 'Циклические, на подбородке', emoji: '🌙'),
    ],
  );

  static const sensitivityStep = OnboardingStep(
    id: OnboardingStepId.sensitivity,
    title: 'Кожа реагирует на новые средства?',
    options: [
      StepOption(id: 'no', title: 'Нет, переносит хорошо', emoji: '👍'),
      StepOption(id: 'sometimes', title: 'Иногда', emoji: '🤷'),
      StepOption(id: 'yes', title: 'Да, часто реагирует', emoji: '⚠️'),
    ],
  );

  static const sensitivityReactionStep = OnboardingStep(
    id: OnboardingStepId.sensitivityReaction,
    title: 'Как именно реагирует?',
    options: [
      StepOption(id: 'redness', title: 'Краснеет'),
      StepOption(id: 'burning', title: 'Печёт / щиплет'),
      StepOption(id: 'breakouts', title: 'Появляются прыщи'),
      StepOption(id: 'flaking', title: 'Шелушение'),
    ],
  );

  // The previous budgetStep ('Какой бюджет на уход?') was dropped — the answer
  // never improved recommendations enough to justify the friction at the end
  // of onboarding. SkinProfile.budget stays on the model and in the DB as a
  // nullable field so existing rows aren't migrated.

  /// First step the user actually sees. Used by the controller's initial
  /// state — kept as a constant so it stays in sync with [next()] / the
  /// total-step estimator below.
  static const OnboardingStepId firstStep = OnboardingStepId.skinType;

  /// Computes the next step from current profile + previously asked id.
  ///
  /// Order rationale: skin-related questions first (they're easy answers
  /// that immediately feel like the app is "learning the skin"), then
  /// gender (only affects messaging tone), then name (lowest-friction once
  /// the user is already invested — better than asking up front).
  static OnboardingStepId next(SkinProfile profile, OnboardingStepId current) {
    switch (current) {
      case OnboardingStepId.skinType:
        if (profile.skinType == 'unknown') {
          return OnboardingStepId.skinTypeHelp;
        }
        return _afterSkinType(profile);
      case OnboardingStepId.skinTypeHelp:
        return _afterSkinType(profile);
      case OnboardingStepId.pores:
        return OnboardingStepId.concerns;
      case OnboardingStepId.concerns:
        if (profile.concerns.contains('acne')) {
          return OnboardingStepId.acneType;
        }
        return OnboardingStepId.sensitivity;
      case OnboardingStepId.acneType:
        return OnboardingStepId.sensitivity;
      case OnboardingStepId.sensitivity:
        if (profile.sensitivity == 'yes') {
          return OnboardingStepId.sensitivityReaction;
        }
        return OnboardingStepId.gender;
      case OnboardingStepId.sensitivityReaction:
        return OnboardingStepId.gender;
      case OnboardingStepId.gender:
        return OnboardingStepId.name;
      case OnboardingStepId.name:
        return OnboardingStepId.done;
      case OnboardingStepId.done:
        return OnboardingStepId.done;
    }
  }

  /// Total step count for the current branch — used by the progress bar
  /// to avoid the hard-coded "6" that broke when the flow branched. Walks
  /// the [next()] graph from [firstStep] using the running profile to
  /// resolve the same conditionals the user will hit.
  static int totalStepsFor(SkinProfile profile) {
    var count = 0;
    var step = firstStep;
    while (step != OnboardingStepId.done) {
      count++;
      step = next(profile, step);
      // Safety: every branch eventually reaches done; cap to avoid an
      // infinite loop if a future edit introduces a cycle.
      if (count > 20) break;
    }
    return count;
  }

  static OnboardingStepId _afterSkinType(SkinProfile profile) {
    if (profile.skinType == 'oily' || profile.skinType == 'combo') {
      return OnboardingStepId.pores;
    }
    return OnboardingStepId.concerns;
  }

  static OnboardingStep stepFor(OnboardingStepId id) {
    switch (id) {
      case OnboardingStepId.name:
        return nameStep;
      case OnboardingStepId.gender:
        return genderStep;
      case OnboardingStepId.skinType:
        return skinTypeStep;
      case OnboardingStepId.skinTypeHelp:
        return skinTypeHelpStep;
      case OnboardingStepId.pores:
        return poresStep;
      case OnboardingStepId.concerns:
        return concernsStep;
      case OnboardingStepId.acneType:
        return acneTypeStep;
      case OnboardingStepId.sensitivity:
        return sensitivityStep;
      case OnboardingStepId.sensitivityReaction:
        return sensitivityReactionStep;
      case OnboardingStepId.done:
        return sensitivityReactionStep;
    }
  }
}
