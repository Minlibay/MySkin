# MySkin

AI-powered skincare app with two modes: Standard (one-shot) and Dermatologist 2.0 (state-machine driven dialog).

## Run

```bash
flutter pub get
flutter run
```

By default uses `MockAIService` (no API key needed). To use real GigaChat:

1. In `lib/main.dart` set `kUseMockAI = false`.
2. Run with: `flutter run --dart-define=GIGACHAT_AUTH_KEY=<base64-encoded-client_id:client_secret>`

## Architecture

```
lib/
  core/
    theme/        # colors, typography, spacing, theme
    widgets/      # AppButton, AppCard, SelectionCard, AppChip, RoutineCard, BreathingLoader
  features/
    onboarding/   # branching quiz (skin type → pores → concerns → ...)
    home/         # mode picker
    routine/      # result + AI loading screen
    ai/
      domain/     # AIService abstraction, RoutineResult, DermResponse
      data/       # GigachatService, MockAIService
    derm2/
      domain/     # DermPhase enum, DermState
      presentation/ # DermStateMachineController + screen
```

### Why Riverpod
- `StateNotifier` lets the Derm 2.0 state machine be unit-tested without a widget tree (see `test/derm_state_machine_test.dart`).
- `autoDispose` cleanly resets session state when the user leaves Derm 2.0.
- `Provider.overrideWithValue` swaps `MockAIService` ↔ `GigachatService` at the root with no codegen.

### State machine
`DermStateMachineController` implements the spec:

```
INIT → COLLECTING_DATA → ANALYZING
ANALYZING → NEED_CLARIFICATION (confidence < 0.85)
ANALYZING → READY_TO_RECOMMEND → GENERATING_ROUTINE → SHOW_RESULT
NEED_CLARIFICATION → COLLECTING_CLARIFICATION → ANALYZING (loop, capped at 4)
SHOW_RESULT → FOLLOW_UP → ANALYZING (loop)
```

Confidence threshold: `0.85`. Loop cap: `4` clarifications, after which the controller forces a recommendation to avoid endless interrogation.

## Tests

```bash
flutter test
```
