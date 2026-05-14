import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';

/// Short same-day questionnaire shown before generating a quick routine.
/// Three single-choice questions, all on one scrollable screen — emphasises
/// 'пара вопросов и готов' over the heavier Лина-диалог flow.
class QuickCheckInScreen extends StatefulWidget {
  const QuickCheckInScreen({
    super.key,
    required this.onBack,
    required this.onSubmit,
  });

  final VoidCallback onBack;

  /// Fires with the three labelled answers in Russian so the prompt at the
  /// backend reads naturally without further mapping.
  final void Function(Map<String, String> answers) onSubmit;

  @override
  State<QuickCheckInScreen> createState() => _QuickCheckInScreenState();
}

class _QuickCheckInScreenState extends State<QuickCheckInScreen> {
  String? _mood;
  String? _notice;
  String? _focus;

  static const _moods = <_Option>[
    _Option('Сияет', '☀️'),
    _Option('Стабильно', '🌸'),
    _Option('Тонко', '🫧'),
    _Option('Тяжко', '🌧️'),
  ];
  static const _notices = <_Option>[
    _Option('Раздражение / краснота', '🔴'),
    _Option('Высыпания', '🩹'),
    _Option('Усталая, тусклая', '🌙'),
    _Option('Сухость / стянутость', '🌵'),
    _Option('Ничего особенного', '✿'),
  ];
  static const _focuses = <_Option>[
    _Option('Минимальный уход', '💧'),
    _Option('Восстановление', '🌿'),
    _Option('Подсияй', '✨'),
    _Option('Успокоить', '☁️'),
  ];

  bool get _canSubmit =>
      _mood != null && _notice != null && _focus != null;

  void _submit() {
    if (!_canSubmit) return;
    widget.onSubmit({
      'mood': _mood!,
      'notice': _notice!,
      'focus': _focus!,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.blush)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm, AppSpacing.sm, AppSpacing.lg, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            size: 20),
                        color: AppColors.textPrimary,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Expanded(
                        child: Text('Чек-ин', style: AppTypography.h1),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                    children: [
                      Text(
                        'Пара вопросов про сейчас — учту в подборе.',
                        style: AppTypography.bodySecondary
                            .copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _Group(
                        eyebrow: 'Кожа сегодня',
                        options: _moods,
                        selected: _mood,
                        onSelect: (v) => setState(() => _mood = v),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _Group(
                        eyebrow: 'Что замечаешь',
                        options: _notices,
                        selected: _notice,
                        onSelect: (v) => setState(() => _notice = v),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _Group(
                        eyebrow: 'Хочется сегодня',
                        options: _focuses,
                        selected: _focus,
                        onSelect: (v) => setState(() => _focus = v),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.xs, AppSpacing.lg, AppSpacing.lg),
                  child: AppButton(
                    label: 'Подобрать уход',
                    onPressed: _canSubmit ? _submit : null,
                    trailingIcon: Icons.auto_awesome_rounded,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Option {
  const _Option(this.title, this.emoji);
  final String title;
  final String emoji;
}

class _Group extends StatelessWidget {
  const _Group({
    required this.eyebrow,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String eyebrow;
  final List<_Option> options;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EyebrowText(eyebrow, color: AppColors.roseDeep),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              _Chip(
                option: o,
                active: selected == o.title,
                onTap: () => onSelect(o.title),
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.option,
    required this.active,
    required this.onTap,
  });
  final _Option option;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.roseDeep : AppColors.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active
                  ? AppColors.roseDeep
                  : AppColors.dividerStrong,
            ),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(option.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Text(
                option.title,
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w500,
                  color: active ? AppColors.surface : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
