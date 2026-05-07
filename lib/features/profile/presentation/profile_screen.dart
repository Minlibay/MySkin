import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../ai/domain/models.dart';
import '../../api/backend_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/user_settings.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.onBack,
    required this.onRetake,
    required this.onOpenShelf,
    required this.onOpenProgress,
    required this.onProfileUpdated,
    this.onOpenRoutineHistory,
  });

  final SkinProfile profile;
  final VoidCallback onBack;
  final VoidCallback onRetake;
  final VoidCallback onOpenShelf;
  final VoidCallback onOpenProgress;
  final ValueChanged<SkinProfile> onProfileUpdated;
  final VoidCallback? onOpenRoutineHistory;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  UserSettings _settings = const UserSettings();
  bool _loaded = false;
  late SkinProfile _profile = widget.profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(backendApiProvider).getSettings();
      if (!mounted) return;
      setState(() {
        _settings = s;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _save(UserSettings updated) async {
    setState(() => _settings = updated);
    try {
      await ref.read(backendApiProvider).updateSettings(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $e')),
      );
    }
  }

  Future<void> _updateProfile(SkinProfile next) async {
    final prev = _profile;
    setState(() => _profile = next);
    try {
      await ref.read(backendApiProvider).putProfile(next);
      widget.onProfileUpdated(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _profile = prev);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $e')),
      );
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _profile.name ?? '');
    final newName = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text('Как тебя зовут?', style: AppTypography.h2),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Имя'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    await _updateProfile(_profile.copyWith(name: newName));
  }

  Future<void> _editSkinType() async {
    const options = [
      ('dry', 'Сухая', '🌵'),
      ('oily', 'Жирная', '🫧'),
      ('combo', 'Комбинированная', '🪞'),
      ('normal', 'Нормальная', '🌸'),
      ('sensitive', 'Чувствительная', '⚠️'),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.dividerStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Text('Тип кожи', style: AppTypography.h2),
            ),
            for (final o in options)
              ListTile(
                leading: Text(o.$3,
                    style: const TextStyle(fontSize: 22)),
                title: Text(o.$2, style: AppTypography.body),
                trailing: _profile.skinType == o.$1
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.roseDeep)
                    : null,
                onTap: () => Navigator.pop(ctx, o.$1),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null || picked == _profile.skinType) return;
    await _updateProfile(_profile.copyWith(skinType: picked));
  }

  Future<void> _exportData() async {
    try {
      final data = await ref.read(backendApiProvider).exportData();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Все твои данные скопированы в буфер обмена')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выгрузить: $e')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text('Удалить аккаунт?', style: AppTypography.h2),
        content: Text(
          'Это удалит профиль, все рекомендации, отметки и полку. Действие необратимо.',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.warning),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(backendApiProvider).deleteAccount();
      if (!mounted) return;
      await ref.read(authControllerProvider.notifier).logout();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $e')),
      );
    }
  }

  Future<void> _pickTime({
    required String label,
    required String current,
    required ValueChanged<String> onPick,
  }) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: label,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.roseDeep,
            onPrimary: Colors.white,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child ?? const SizedBox(),
      ),
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    onPick('$hh:$mm');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final name = _profile.name?.trim().isNotEmpty == true
        ? _profile.name!
        : 'Без имени';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.champagne)),
          SafeArea(
            child: Column(
              children: [
                _Header(onBack: widget.onBack),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0,
                        AppSpacing.lg, AppSpacing.xxl),
                    children: [
                      _ProfileHero(
                        name: name,
                        phone: user?.phone ?? '',
                        onEditName: _editName,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _SectionTitle('Уход'),
                      _Tile(
                        icon: Icons.spa_rounded,
                        title: 'Тип кожи',
                        trailing: _skinTypeLabel(_profile.skinType),
                        onTap: _editSkinType,
                      ),
                      _Tile(
                        icon: Icons.flag_rounded,
                        title: 'Мои цели',
                        trailing: _profile.concerns.isEmpty
                            ? '—'
                            : '${_profile.concerns.length}',
                      ),
                      _Tile(
                        icon: Icons.inventory_2_rounded,
                        title: 'Моя полка',
                        onTap: widget.onOpenShelf,
                      ),
                      if (widget.onOpenRoutineHistory != null)
                        _Tile(
                          icon: Icons.history_rounded,
                          title: 'Мои уходы',
                          onTap: widget.onOpenRoutineHistory,
                        ),
                      _Tile(
                        icon: Icons.trending_up_rounded,
                        title: 'История и прогресс',
                        onTap: widget.onOpenProgress,
                      ),
                      _Tile(
                        icon: Icons.refresh_rounded,
                        title: 'Пройти анкету заново',
                        onTap: widget.onRetake,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _SectionTitle('Уведомления'),
                      _SwitchTile(
                        icon: Icons.wb_sunny_rounded,
                        title: 'Утренний ритуал',
                        subtitle: _settings.notifications.morning
                            ? _settings.notifications.morningTime
                            : 'выкл',
                        value: _settings.notifications.morning,
                        onChanged: (v) => _save(_settings.copyWith(
                          notifications: _settings.notifications
                              .copyWith(morning: v),
                        )),
                        onTapTime: _settings.notifications.morning
                            ? () => _pickTime(
                                  label: 'Утром в',
                                  current:
                                      _settings.notifications.morningTime,
                                  onPick: (t) => _save(
                                    _settings.copyWith(
                                      notifications: _settings.notifications
                                          .copyWith(morningTime: t),
                                    ),
                                  ),
                                )
                            : null,
                      ),
                      _SwitchTile(
                        icon: Icons.nightlight_round,
                        title: 'Вечерний ритуал',
                        subtitle: _settings.notifications.evening
                            ? _settings.notifications.eveningTime
                            : 'выкл',
                        value: _settings.notifications.evening,
                        onChanged: (v) => _save(_settings.copyWith(
                          notifications: _settings.notifications
                              .copyWith(evening: v),
                        )),
                        onTapTime: _settings.notifications.evening
                            ? () => _pickTime(
                                  label: 'Вечером в',
                                  current:
                                      _settings.notifications.eveningTime,
                                  onPick: (t) => _save(
                                    _settings.copyWith(
                                      notifications: _settings.notifications
                                          .copyWith(eveningTime: t),
                                    ),
                                  ),
                                )
                            : null,
                      ),
                      if (!_loaded) ...[
                        const SizedBox(height: AppSpacing.xs),
                        const _LoadingHint(),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      const _SectionTitle('Конфиденциальность'),
                      _Tile(
                        icon: Icons.download_rounded,
                        title: 'Экспорт моих данных',
                        subtitle:
                            'Скопирует JSON со всеми твоими данными',
                        onTap: _exportData,
                      ),
                      _Tile(
                        icon: Icons.delete_outline_rounded,
                        title: 'Удалить аккаунт',
                        danger: true,
                        onTap: _confirmDelete,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _SectionTitle('О приложении'),
                      _Tile(
                        icon: Icons.info_outline_rounded,
                        title: 'Версия',
                        trailing: '0.1.0',
                      ),
                      _Tile(
                        icon: Icons.menu_book_rounded,
                        title: 'Политика конфиденциальности',
                        onTap: () {/* TODO link */},
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _LogoutButton(
                        onLogout: () => ref
                            .read(authControllerProvider.notifier)
                            .logout(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _skinTypeLabel(String? id) => switch (id) {
        'dry' => 'Сухая',
        'oily' => 'Жирная',
        'combo' => 'Комбинированная',
        'normal' => 'Нормальная',
        'sensitive' => 'Чувствительная',
        _ => '—',
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Material(
              color: Colors.white.withOpacity(0.7),
              shape: const CircleBorder(
                  side: BorderSide(color: AppColors.divider)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack,
                child: const Icon(Icons.arrow_back_ios_new, size: 16),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.phone,
    required this.onEditName,
  });
  final String name;
  final String phone;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.blush2],
            ),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryAccent.withOpacity(0.5),
                blurRadius: 28,
                offset: const Offset(0, 12),
                spreadRadius: -8,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            name[0].toUpperCase(),
            style: AppTypography.serifItalic(
              fontSize: 38,
              color: AppColors.roseDeep,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        InkWell(
          onTap: onEditName,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: AppTypography.h1),
                const SizedBox(width: 6),
                const Icon(Icons.edit_rounded,
                    size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(phone, style: AppTypography.caption),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: EyebrowText(text, color: AppColors.textSecondary),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.warning : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                vertical: 14, horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: danger
                        ? AppColors.warning.withOpacity(0.15)
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTypography.body
                              .copyWith(color: color)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: AppTypography.caption
                                .copyWith(fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  Text(
                    trailing!,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                ],
                if (onTap != null)
                  const Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.onTapTime,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onTapTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: 10, horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.roseDeep),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.body),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: onTapTime,
                    child: Text(
                      subtitle,
                      style: AppTypography.caption.copyWith(
                        color: onTapTime != null
                            ? AppColors.roseDeep
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.roseDeep,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingHint extends StatelessWidget {
  const _LoadingHint();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('Загружаем настройки…',
            style: AppTypography.caption.copyWith(fontSize: 12)),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onLogout});
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onLogout,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.logout_rounded,
                  color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 8),
              Text('Выйти из аккаунта',
                  style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
