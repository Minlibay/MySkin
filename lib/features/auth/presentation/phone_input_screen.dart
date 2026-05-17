import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../legal/presentation/legal_viewer_screen.dart';
import 'auth_controller.dart';
import 'phone_formatter.dart';

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  final _controller = TextEditingController(text: '+7 (');
  bool _agreed = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _e164 => RuPhoneFormatter.extractE164(_controller.text);

  Future<void> _submit() async {
    final phone = _e164;
    if (phone == null || !_agreed) return;
    await ref.read(authControllerProvider.notifier).requestCode(phone);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final canSubmit = _e164 != null && _agreed && !state.busy;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.sunrise)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              const EyebrowText('MySkin', color: AppColors.roseDeep),
              const SizedBox(height: AppSpacing.sm),
              Text.rich(
                TextSpan(
                  style: AppTypography.display,
                  children: [
                    const TextSpan(text: 'Бережный уход '),
                    TextSpan(
                      text: 'каждый день',
                      style: AppTypography.serifItalic(fontSize: 36).copyWith(
                        letterSpacing: -0.36,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Введи номер — пришлём код для входа.',
                style: AppTypography.bodySecondary.copyWith(fontSize: 15),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  style: AppTypography.h2,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\(\)\s-]')),
                    RuPhoneFormatter(),
                  ],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '+7 (___) ___-__-__',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (canSubmit) _submit();
                  },
                ),
              ),
              if (state.errorCode != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_errorText(state.errorCode!),
                    style: AppTypography.caption
                        .copyWith(color: AppColors.danger)),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _agreed,
                      activeColor: AppColors.primaryAccent,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _LegalConsentText(onOpenLegal: _openLegal)),
                ],
              ),
              const Spacer(),
              AppButton(
                label: 'Получить код',
                onPressed: canSubmit ? _submit : null,
                loading: state.busy,
                trailingIcon: Icons.arrow_forward_rounded,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
            ),
          ),
        ],
      ),
    );
  }

  void _openLegal(String docKey, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalViewerScreen(
          docKey: docKey,
          title: title,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  String _errorText(String code) => switch (code) {
        'invalid_phone' => 'Проверь номер',
        'too_many_requests' => 'Подожди немного перед повторной отправкой',
        'sms_provider_failed' => 'Не удалось отправить SMS, попробуй ещё раз',
        'network_error' => 'Нет связи с сервером',
        _ => 'Что-то пошло не так',
      };
}

/// Checkbox label with three clickable legal-doc links.
/// Wraps onto multiple lines, tapping any underlined fragment opens the
/// document in a LegalViewerScreen.
class _LegalConsentText extends StatefulWidget {
  const _LegalConsentText({required this.onOpenLegal});
  final void Function(String key, String title) onOpenLegal;

  @override
  State<_LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<_LegalConsentText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _tap(String key, String title) {
    final r = TapGestureRecognizer()
      ..onTap = () => widget.onOpenLegal(key, title);
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = AppTypography.caption.copyWith(
      color: AppColors.roseDeep,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.roseDeep,
    );
    return Text.rich(
      TextSpan(
        style: AppTypography.caption,
        children: [
          const TextSpan(text: 'Продолжая, принимаю '),
          TextSpan(
            text: 'Пользовательское соглашение',
            style: linkStyle,
            recognizer: _tap('legal_terms', 'Пользовательское соглашение'),
          ),
          const TextSpan(text: ', '),
          TextSpan(
            text: 'Политику конфиденциальности',
            style: linkStyle,
            recognizer:
                _tap('legal_privacy', 'Политика конфиденциальности'),
          ),
          const TextSpan(text: ' и '),
          TextSpan(
            text: 'Согласие на обработку персональных данных',
            style: linkStyle,
            recognizer: _tap(
                'legal_consent', 'Согласие на обработку персональных данных'),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}
