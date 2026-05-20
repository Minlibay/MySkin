import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/eyebrow_text.dart';
import '../widgets/glow_background.dart';
import 'permissions.dart';

/// One-shot screen shown the first time the app runs (after auth) that
/// asks for camera/mic/photos/notifications in a single sweep. Honours
/// platform conventions: we explain WHY for each permission first, then
/// hand off to the OS dialog. After the user decides — grant or deny —
/// we mark the initial-asked flag and never show this screen again.
class PermissionsIntroScreen extends StatefulWidget {
  const PermissionsIntroScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<PermissionsIntroScreen> createState() => _PermissionsIntroScreenState();
}

class _PermissionsIntroScreenState extends State<PermissionsIntroScreen> {
  bool _busy = false;

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      await AppPermissions.instance.requestInitial();
    } finally {
      if (mounted) widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <_PermItem>[
      const _PermItem(
        icon: Icons.camera_alt_outlined,
        title: 'Камера',
        sub: 'Чтобы анализ кожи прошёл по твоей селфи.',
      ),
      const _PermItem(
        icon: Icons.mic_none_rounded,
        title: 'Микрофон',
        sub: 'Чтобы можно было надиктовать вопрос Лине голосом.',
      ),
      const _PermItem(
        icon: Icons.notifications_none_rounded,
        title: 'Уведомления',
        sub: 'Тихие напоминания об утреннем и вечернем ритуале.',
      ),
      if (Platform.isIOS)
        const _PermItem(
          icon: Icons.photo_library_outlined,
          title: 'Фото',
          sub: 'Чтобы загрузить старое фото для повторного анализа.',
        ),
    ];

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
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const EyebrowText('Доступы',
                      color: AppColors.roseDeep),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: 'Чтобы Лина ',
                          style: AppTypography.h1.copyWith(fontSize: 28)),
                      TextSpan(
                        text: 'работала',
                        style:
                            AppTypography.serifItalic(fontSize: 28),
                      ),
                      TextSpan(
                          text: ',\nей нужно немного доступа',
                          style: AppTypography.h1.copyWith(fontSize: 28)),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Спросим один раз. Откажешь — это ок: каждый '
                    'функционал потом сам подскажет, когда доступ '
                    'понадобится.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (_, i) => _PermTile(item: items[i]),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _request,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.roseDeep,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const StadiumBorder(),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : Text('Продолжить',
                              style: AppTypography.button),
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

class _PermItem {
  const _PermItem({
    required this.icon,
    required this.title,
    required this.sub,
  });
  final IconData icon;
  final String title;
  final String sub;
}

class _PermTile extends StatelessWidget {
  const _PermTile({required this.item});
  final _PermItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.blush,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon,
                color: AppColors.roseDeep, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 2),
                Text(item.sub,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns true once the system prompts shown by [PermissionsIntroScreen]
/// don't need to be displayed at app startup (either previously asked or
/// the user dismissed). Used by the shell to decide whether to insert
/// the intro between auth and home.
Future<bool> shouldShowPermissionsIntro() async =>
    !(await AppPermissions.instance.isInitialAsked());

/// Convenience accessor — re-export for callers that don't want to import
/// permission_handler directly.
typedef AppPermission = Permission;
