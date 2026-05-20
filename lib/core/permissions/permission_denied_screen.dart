import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/eyebrow_text.dart';
import '../widgets/glow_background.dart';
import 'permissions.dart';

/// Full-screen blocker shown when a feature can't continue because the
/// user previously denied a permission and iOS/Android no longer surfaces
/// the system prompt. The only way forward is the system settings — the
/// big button opens them; the back button returns to the previous screen.
class PermissionDeniedScreen extends StatelessWidget {
  const PermissionDeniedScreen({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    required this.onBack,
  });

  /// Build a camera-permission variant with copy tuned for the scan flow.
  factory PermissionDeniedScreen.camera({required VoidCallback onBack}) =>
      PermissionDeniedScreen(
        icon: Icons.camera_alt_outlined,
        title: 'Нужен доступ к камере',
        body: 'Чтобы Лина проанализировала кожу, ей нужно увидеть твоё '
            'селфи. Открой настройки и включи доступ к камере — после '
            'этого вернись сюда.',
        onBack: onBack,
      );

  /// Microphone variant — used when voice input in chat is blocked.
  factory PermissionDeniedScreen.microphone({required VoidCallback onBack}) =>
      PermissionDeniedScreen(
        icon: Icons.mic_none_rounded,
        title: 'Нужен доступ к микрофону',
        body: 'Чтобы надиктовать вопрос голосом, разреши доступ к '
            'микрофону в настройках. Печатать в чате можно и без него.',
        onBack: onBack,
      );

  /// Notifications variant — used when the user opts in to reminders but
  /// the OS-level permission is denied.
  factory PermissionDeniedScreen.notifications(
          {required VoidCallback onBack}) =>
      PermissionDeniedScreen(
        icon: Icons.notifications_none_rounded,
        title: 'Уведомления отключены',
        body: 'Без них мы не сможем мягко напомнить про утренний или '
            'вечерний ритуал. Включи уведомления в настройках, если '
            'хочешь получать напоминания.',
        onBack: onBack,
      );

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: GlowBackground(variant: GlowVariant.blush),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: Material(
                          color: AppColors.surface,
                          shape: const CircleBorder(
                              side: BorderSide(color: AppColors.divider)),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onBack,
                            child: const Icon(Icons.arrow_back_ios_new,
                                size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.blush,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(icon,
                        color: AppColors.roseDeep, size: 44),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const EyebrowText('Доступ',
                      color: AppColors.roseDeep),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTypography.h1.copyWith(fontSize: 28),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          AppPermissions.instance.openSettings(),
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: Text('Открыть настройки',
                          style: AppTypography.button),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.roseDeep,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: onBack,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Назад'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
