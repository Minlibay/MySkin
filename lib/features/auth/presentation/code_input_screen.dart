import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import 'auth_controller.dart';

class CodeInputScreen extends ConsumerStatefulWidget {
  const CodeInputScreen({super.key, required this.phone});
  final String phone;

  @override
  ConsumerState<CodeInputScreen> createState() => _CodeInputScreenState();
}

class _CodeInputScreenState extends ConsumerState<CodeInputScreen> {
  static const _length = 4;
  late final List<TextEditingController> _cellCtrls =
      List.generate(_length, (_) => TextEditingController());
  late final List<FocusNode> _cellNodes =
      List.generate(_length, (_) => FocusNode());

  Timer? _resendTimer;
  int _resendIn = 60;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cellNodes.first.requestFocus();
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
    for (final c in _cellCtrls) {
      c.dispose();
    }
    for (final n in _cellNodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _cellCtrls.map((c) => c.text).join();

  void _onChanged(int i, String v) {
    if (v.length > 1) {
      // pasted whole code
      final digits = v.replaceAll(RegExp(r'\D'), '');
      for (var k = 0; k < _length; k++) {
        _cellCtrls[k].text = k < digits.length ? digits[k] : '';
      }
      _cellNodes[(_length - 1)].requestFocus();
      setState(() {});
      if (_code.length == _length) _submit();
      return;
    }
    if (v.isNotEmpty && i < _length - 1) {
      _cellNodes[i + 1].requestFocus();
    }
    setState(() {});
    if (_code.length == _length) _submit();
  }

  void _onKey(int i, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _cellCtrls[i].text.isEmpty &&
        i > 0) {
      _cellCtrls[i - 1].clear();
      _cellNodes[i - 1].requestFocus();
      setState(() {});
    }
  }

  Future<void> _submit() async {
    final code = _code;
    if (code.length != _length) return;
    await ref.read(authControllerProvider.notifier).verify(code);
  }

  Future<void> _resend() async {
    if (_resendIn > 0) return;
    await ref.read(authControllerProvider.notifier).resend();
    _startResendTimer();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final hasError = state.errorCode == 'wrong_code';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () =>
              ref.read(authControllerProvider.notifier).backToPhone(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Введи код', style: AppTypography.h1),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Отправили на ${widget.phone}',
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                    _length, (i) => _Cell(index: i, hasError: hasError, state: this)),
              ),
              if (state.errorCode != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _errorText(state.errorCode!),
                  style:
                      AppTypography.caption.copyWith(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Center(
                child: _resendIn > 0
                    ? Text('Отправить код снова через $_resendIn с',
                        style: AppTypography.caption)
                    : TextButton(
                        onPressed: _resend,
                        child: const Text('Отправить ещё раз'),
                      ),
              ),
              const Spacer(),
              if (state.busy)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: CircularProgressIndicator(
                      color: AppColors.primaryAccent,
                    ),
                  ),
                )
              else
                AppButton(
                  label: 'Подтвердить',
                  onPressed: _code.length == _length ? _submit : null,
                ),
              const SizedBox(height: AppSpacing.md),
            ],
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

class _Cell extends StatefulWidget {
  const _Cell({required this.index, required this.hasError, required this.state});
  final int index;
  final bool hasError;
  final _CodeInputScreenState state;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  // Hidden focus node for the KeyboardListener. Owned by this state so it's
  // created once per cell instead of every rebuild.
  late final FocusNode _kbNode = FocusNode(skipTraversal: true, debugLabel: 'cell-${widget.index}-kb');

  @override
  void initState() {
    super.initState();
    widget.state._cellNodes[widget.index].addListener(_repaint);
  }

  @override
  void dispose() {
    widget.state._cellNodes[widget.index].removeListener(_repaint);
    _kbNode.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.state._cellCtrls[widget.index];
    final node = widget.state._cellNodes[widget.index];
    final filled = ctrl.text.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 64,
      height: 72,
      decoration: BoxDecoration(
        color: filled ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: widget.hasError
              ? AppColors.danger
              : (node.hasFocus
                  ? AppColors.primaryAccent
                  : AppColors.divider),
          width: node.hasFocus ? 1.5 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: KeyboardListener(
        focusNode: _kbNode,
        onKeyEvent: (e) => widget.state._onKey(widget.index, e),
        child: TextField(
          controller: ctrl,
          focusNode: node,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          style: AppTypography.h1.copyWith(fontSize: 32),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
          ),
          onChanged: (v) => widget.state._onChanged(widget.index, v),
        ),
      ),
    );
  }
}
