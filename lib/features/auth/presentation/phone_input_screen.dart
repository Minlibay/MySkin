import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
  // Consent is OFF by default. RF practice frowns on pre-ticked opt-ins —
  // it implies the user didn't actively accept. Forces a deliberate tap.
  bool _agreed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _e164 => RuPhoneFormatter.extractE164(_controller.text);

  Future<void> _submit() async {
    final phone = _e164;
    if (phone == null || !_agreed) return;
    HapticFeedback.lightImpact();
    await ref.read(authControllerProvider.notifier).requestCode(phone);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final canSubmit = _e164 != null && _agreed && !state.busy;

    return Scaffold(
      backgroundColor: AppColors.background,
      // Keyboard pushes the body up. Button sits in the column right above
      // the keyboard inset rather than flush at the bottom of the screen.
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.sunrise)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  const EyebrowText('Моя Кожа', color: AppColors.roseDeep),
                  const SizedBox(height: AppSpacing.sm),
                  Text.rich(
                    TextSpan(
                      style: AppTypography.display,
                      children: [
                        const TextSpan(text: 'Бережный уход '),
                        TextSpan(
                          text: 'каждый день',
                          style:
                              AppTypography.serifItalic(fontSize: 36).copyWith(
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
                      autofillHints: const [AutofillHints.telephoneNumber],
                      autofocus: true,
                      style: AppTypography.h2,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9+\(\)\s-]')),
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
                  _ConsentRow(
                    agreed: _agreed,
                    onToggle: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _agreed = v);
                    },
                    onOpenAll: () => _openLegalSheet(context),
                  ),
                  const Spacer(),
                  AppButton(
                    label: 'Получить код',
                    onPressed: canSubmit ? _submit : null,
                    loading: state.busy,
                    trailingIcon: Icons.arrow_forward_rounded,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openLegalSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.dividerStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Правовые документы', style: AppTypography.h2),
              const SizedBox(height: 4),
              Text(
                'Регистрируясь, ты принимаешь все четыре.',
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.md),
              _LegalSheetTile(
                title: 'Пользовательское соглашение',
                docKey: 'legal_terms',
                ctx: ctx,
              ),
              _LegalSheetTile(
                title: 'Политика конфиденциальности',
                docKey: 'legal_privacy',
                ctx: ctx,
              ),
              _LegalSheetTile(
                title: 'Согласие на обработку персональных данных',
                docKey: 'legal_consent',
                ctx: ctx,
              ),
              _LegalSheetTile(
                title: 'Медицинская оговорка',
                docKey: 'legal_medical',
                ctx: ctx,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
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

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.agreed,
    required this.onToggle,
    required this.onOpenAll,
  });
  final bool agreed;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final linkStyle = AppTypography.caption.copyWith(
      color: AppColors.roseDeep,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.roseDeep,
      fontWeight: FontWeight.w500,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Checkbox(
            value: agreed,
            activeColor: AppColors.primaryAccent,
            onChanged: (v) => onToggle(v ?? false),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: GestureDetector(
            onTap: () => onToggle(!agreed),
            behavior: HitTestBehavior.opaque,
            child: Text.rich(
              TextSpan(
                style: AppTypography.caption,
                children: [
                  const TextSpan(text: 'Принимаю '),
                  TextSpan(
                    text: 'условия использования',
                    style: linkStyle,
                    recognizer: _SheetTapRecognizer(onOpenAll),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tiny holder so we can wire a tap recognizer inside an inline TextSpan
/// without making the consumer widget Stateful.
class _SheetTapRecognizer extends TapGestureRecognizer {
  _SheetTapRecognizer(VoidCallback onTap) {
    this.onTap = onTap;
  }
}

class _LegalSheetTile extends StatelessWidget {
  const _LegalSheetTile({
    required this.title,
    required this.docKey,
    required this.ctx,
  });
  final String title;
  final String docKey;
  final BuildContext ctx;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: AppTypography.body),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textSecondary),
      onTap: () {
        Navigator.pop(ctx);
        Navigator.of(ctx).push(MaterialPageRoute<void>(
          builder: (c) => LegalViewerScreen(
            docKey: docKey,
            title: title,
            onBack: () => Navigator.of(c).pop(),
          ),
        ));
      },
    );
  }
}
