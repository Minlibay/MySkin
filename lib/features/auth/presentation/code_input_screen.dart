import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import 'auth_controller.dart';

/// 4-digit OTP screen.
///
/// Design notes — fixed from the previous per-cell TextField implementation:
///
/// 1. **One hidden TextField backs four visual cells.** The old version
///    used four separate TextFields. Each digit triggered a focus change,
///    and on iOS/Android the soft keyboard briefly tore down and re-opened
///    on every focus shift — so the user couldn't type the code without
///    the keyboard blinking. A single field with `maxLength: 4` keeps the
///    keyboard attached for the entire entry and lets the OS autofill bar
///    paste a 4-digit SMS code in one tap.
///
/// 2. **Autofill.** `AutofillHints.oneTimeCode` + `keyboardType.number`
///    + `textContentType` (handled by Flutter on iOS automatically given
///    the hint) lets iOS surface the OTP from the most recent SMS on the
///    keyboard suggestion strip, and on Android the IME's OTP detection
///    populates the field. Wrapped in `AutofillGroup`.
///
/// 3. **Error feedback.** Wrong code shakes the cells, fires a haptic,
///    and clears the field so the user can re-enter without manual tap.
const _codeLength = 4;

class CodeInputScreen extends ConsumerStatefulWidget {
  const CodeInputScreen({super.key, required this.phone});
  final String phone;

  @override
  ConsumerState<CodeInputScreen> createState() => _CodeInputScreenState();
}

class _CodeInputScreenState extends ConsumerState<CodeInputScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _resendTimer;
  int _resendIn = 60;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shake;

  // Mirror of `auth.errorCode` from the previous build so we can detect a
  // freshly-arrived error and shake exactly once instead of on every
  // rebuild while the same error sits in state.
  String? _lastErrorCode;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendIn <= 1) {
        t.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _controller.dispose();
    _focus.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  String get _code => _controller.text;

  void _onChanged(String v) {
    // Strip any non-digit the IME might inject (rare, but autofill can pass
    // spaces or hyphens from SMS bodies like "Your code is 1 2 3 4").
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits != v) {
      _controller.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }
    setState(() {});
    if (digits.length == _codeLength) {
      _submit();
    }
  }

  Future<void> _submit() async {
    if (_code.length != _codeLength) return;
    HapticFeedback.lightImpact();
    await ref.read(authControllerProvider.notifier).verify(_code);
  }

  Future<void> _resend() async {
    if (_resendIn > 0) return;
    HapticFeedback.selectionClick();
    await ref.read(authControllerProvider.notifier).resend();
    _startResendTimer();
  }

  void _triggerErrorFeedback() {
    HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);
    // Clear the field so the user just retypes — saves a manual long-press.
    _controller.clear();
    setState(() {});
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) _focus.requestFocus();
    });
  }

  String _resendLabel() {
    if (_resendIn <= 0) return '';
    final m = _resendIn ~/ 60;
    final s = _resendIn % 60;
    return '0:${s.toString().padLeft(2, '0')}'.replaceFirst('0:', '$m:');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    // Detect a freshly-arrived error and trigger shake once.
    if (state.errorCode != null && state.errorCode != _lastErrorCode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerErrorFeedback();
      });
    }
    _lastErrorCode = state.errorCode;
    final hasError = state.errorCode == 'wrong_code';

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () =>
              ref.read(authControllerProvider.notifier).backToPhone(),
        ),
      ),
      body: SafeArea(
        child: AutofillGroup(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Введи код', style: AppTypography.h1),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Отправили на ${widget.phone}',
                  style: AppTypography.bodySecondary,
                ),
                const SizedBox(height: AppSpacing.xl),

                // Stack: the real (invisible) TextField sits underneath
                // the visual cells. We could hide the field with size: 0,
                // but Flutter ignores zero-sized fields for focus on some
                // platforms — full-sized + transparent is the proven
                // pattern (pinput, otp_text_field use the same trick).
                AnimatedBuilder(
                  animation: _shake,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(_shake.value, 0),
                    child: child,
                  ),
                  child: LayoutBuilder(
                    builder: (ctx, c) {
                      final w = ((c.maxWidth - 12.0 * (_codeLength - 1)) /
                              _codeLength)
                          .clamp(48.0, 72.0);
                      final cellHeight = w * 1.12;
                      return SizedBox(
                        height: cellHeight,
                        child: Stack(
                          children: [
                            // Invisible TextField, full row, takes focus &
                            // surface the keyboard / OTP autofill.
                            Opacity(
                              opacity: 0.0,
                              child: SizedBox(
                                height: cellHeight,
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _focus,
                                  autofocus: true,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  maxLength: _codeLength,
                                  showCursor: false,
                                  autofillHints: const [
                                    AutofillHints.oneTimeCode
                                  ],
                                  enableIMEPersonalizedLearning: false,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(
                                        _codeLength),
                                  ],
                                  onChanged: _onChanged,
                                  onSubmitted: (_) => _submit(),
                                  decoration: const InputDecoration(
                                    counterText: '',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                            // Visual cells. IgnorePointer so taps fall
                            // through to the TextField underneath and the
                            // OS keyboard pops up naturally.
                            IgnorePointer(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: List.generate(_codeLength, (i) {
                                  final filled = i < _code.length;
                                  final isCurrent = i == _code.length &&
                                      _focus.hasFocus;
                                  return _CodeCell(
                                    width: w,
                                    height: cellHeight,
                                    digit: filled ? _code[i] : '',
                                    focused: isCurrent,
                                    error: hasError,
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                if (state.errorCode != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _errorText(state.errorCode!),
                    style: AppTypography.caption
                        .copyWith(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Center(
                  child: _resendIn > 0
                      ? Text('Отправить код снова через ${_resendLabel()}',
                          style: AppTypography.caption)
                      : TextButton(
                          onPressed: _resend,
                          child: const Text('Отправить ещё раз'),
                        ),
                ),
                const Spacer(),
                AppButton(
                  label: 'Подтвердить',
                  loading: state.busy,
                  onPressed:
                      _code.length == _codeLength && !state.busy ? _submit : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _errorText(String code) => switch (code) {
        'wrong_code' => 'Неверный код. Попробуй ещё раз.',
        'code_expired' => 'Код истёк. Запроси новый.',
        'too_many_attempts' => 'Слишком много попыток. Запроси новый код.',
        'no_code_pending' => 'Сначала запроси код.',
        'network_error' => 'Нет связи с сервером',
        _ => 'Что-то пошло не так',
      };
}

class _CodeCell extends StatelessWidget {
  const _CodeCell({
    required this.width,
    required this.height,
    required this.digit,
    required this.focused,
    required this.error,
  });
  final double width;
  final double height;
  final String digit;
  final bool focused;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final filled = digit.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: filled ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: error
              ? AppColors.danger
              : (focused ? AppColors.primaryAccent : AppColors.divider),
          width: focused ? 1.5 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1.0)
              .animate(CurvedAnimation(
                  parent: anim, curve: Curves.easeOutBack)),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: filled
            ? Text(
                digit,
                key: ValueKey(digit + width.toString()),
                style: AppTypography.h1.copyWith(fontSize: 32),
              )
            : focused
                ? const _Caret(key: ValueKey('caret'))
                : const SizedBox.shrink(key: ValueKey('empty')),
      ),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret({super.key});

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 2,
        height: 28,
        color: AppColors.roseDeep,
      ),
    );
  }
}
