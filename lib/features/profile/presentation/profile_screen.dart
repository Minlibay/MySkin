import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../ai/domain/models.dart';
import '../../api/backend_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../legal/presentation/legal_viewer_screen.dart';
import '../../notifications/data/local_notifications.dart';
import '../../tutorial/presentation/welcome_tutorial_screen.dart';
import '../domain/user_settings.dart';

/// Profile / settings hub. Re-built from the handoff design — avatar block
/// with edit pencil, stats card (indices), three settings groups (Моё /
/// Лина — мой AI-агент / Аккаунт), and a version footer.
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
    this.onOpenFavorites,
    this.skinScore,
    this.streak,
  });

  final SkinProfile profile;
  final VoidCallback onBack;
  final VoidCallback onRetake;
  final VoidCallback onOpenShelf;
  final VoidCallback onOpenProgress;
  final ValueChanged<SkinProfile> onProfileUpdated;
  final VoidCallback? onOpenRoutineHistory;
  final VoidCallback? onOpenFavorites;

  /// Latest skin index from the most recent scan/routine — drives the centre
  /// stat. Null while bootstrap hasn't loaded a result yet.
  final int? skinScore;

  /// Days-in-a-row streak from `today` — drives the middle stat.
  final int? streak;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  UserSettings _settings = const UserSettings();
  bool _loaded = false;
  int? _shelfCount;
  late SkinProfile _profile = widget.profile;

  /// Bumps every time the avatar is uploaded or removed; appended to the
  /// network URL as ?v= so Flutter's image cache refetches instead of
  /// serving the stale photo.
  int _avatarVersion = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(backendApiProvider);
    try {
      final results = await Future.wait([
        api.getSettings(),
        api.getShelf(),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as UserSettings;
        _shelfCount = (results[1] as List).length;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _save(UserSettings updated) async {
    final wasMorning = _settings.notifications.morning;
    final wasEvening = _settings.notifications.evening;
    setState(() => _settings = updated);
    try {
      await ref.read(backendApiProvider).updateSettings(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $e')),
      );
      return;
    }
    final justEnabled = (updated.notifications.morning && !wasMorning) ||
        (updated.notifications.evening && !wasEvening);
    if (justEnabled) {
      await LocalNotificationsService.instance.requestPermission();
    }
    // ignore: unawaited_futures
    LocalNotificationsService.instance.reschedule(updated.notifications);
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
                leading: Text(o.$3, style: const TextStyle(fontSize: 22)),
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

  Future<void> _editConcerns() async {
    const all = [
      ('acne', 'Акне / прыщи'),
      ('pih', 'Пост-акне, пятна'),
      ('aging', 'Морщины, упругость'),
      ('dullness', 'Тусклый цвет'),
      ('redness', 'Покраснения'),
      ('dehydration', 'Обезвоженность'),
    ];
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        final selected = {..._profile.concerns};
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 8, AppSpacing.lg, AppSpacing.lg),
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
                  const SizedBox(height: 12),
                  Text('Цели и приоритеты', style: AppTypography.h2),
                  const SizedBox(height: 4),
                  Text(
                    'Можно выбрать несколько',
                    style:
                        AppTypography.caption.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in all)
                        _ConcernChip(
                          label: c.$2,
                          active: selected.contains(c.$1),
                          onTap: () => setSheet(() {
                            if (selected.contains(c.$1)) {
                              selected.remove(c.$1);
                            } else {
                              selected.add(c.$1);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: AppColors.roseDeep,
                      borderRadius: BorderRadius.circular(99),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () =>
                            Navigator.pop(ctx, selected.toList()),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          child: Text('Сохранить',
                              style: AppTypography.button),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    if (result == null) return;
    await _updateProfile(_profile.copyWith(concerns: result));
  }

  void _openAvatarSheet() {
    showModalBottomSheet<void>(
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
            ListTile(
              leading: const Icon(Icons.edit_rounded,
                  color: AppColors.textPrimary),
              title: Text('Изменить имя', style: AppTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                _editName();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined,
                  color: AppColors.textPrimary),
              title: Text('Сменить фото', style: AppTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                _pickAvatar();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.warning),
              title: Text('Убрать фото',
                  style: AppTypography.body
                      .copyWith(color: AppColors.warning)),
              onTap: () {
                Navigator.pop(ctx);
                _removeAvatar();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 800,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 4 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фото слишком большое (>4 МБ)')),
      );
      return;
    }
    try {
      await ref.read(backendApiProvider).setAvatar(
            photoBase64: base64Encode(bytes),
            mime: picked.mimeType ?? 'image/jpeg',
          );
      if (!mounted) return;
      setState(() =>
          _avatarVersion = DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не получилось загрузить: $e')),
      );
    }
  }

  Future<void> _removeAvatar() async {
    try {
      await ref.read(backendApiProvider).removeAvatar();
      if (!mounted) return;
      setState(() =>
          _avatarVersion = DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не получилось убрать: $e')),
      );
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _profile.name ?? '');
    final newName = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    await _updateProfile(_profile.copyWith(name: newName));
  }

  void _openReminders() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.dividerStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('Напоминания', style: AppTypography.h2),
                const SizedBox(height: AppSpacing.md),
                _ReminderTile(
                  icon: Icons.wb_sunny_rounded,
                  title: 'Утренний ритуал',
                  enabled: _settings.notifications.morning,
                  time: _settings.notifications.morningTime,
                  onEnabled: (v) {
                    setSheet(() {});
                    _save(_settings.copyWith(
                        notifications:
                            _settings.notifications.copyWith(morning: v)));
                  },
                  onPickTime: () async {
                    final t = await _pickTime(
                        label: 'Утром в',
                        current: _settings.notifications.morningTime);
                    if (t != null) {
                      setSheet(() {});
                      await _save(_settings.copyWith(
                          notifications: _settings.notifications
                              .copyWith(morningTime: t)));
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _ReminderTile(
                  icon: Icons.nightlight_round,
                  title: 'Вечерний ритуал',
                  enabled: _settings.notifications.evening,
                  time: _settings.notifications.eveningTime,
                  onEnabled: (v) {
                    setSheet(() {});
                    _save(_settings.copyWith(
                        notifications:
                            _settings.notifications.copyWith(evening: v)));
                  },
                  onPickTime: () async {
                    final t = await _pickTime(
                        label: 'Вечером в',
                        current: _settings.notifications.eveningTime);
                    if (t != null) {
                      setSheet(() {});
                      await _save(_settings.copyWith(
                          notifications: _settings.notifications
                              .copyWith(eveningTime: t)));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPrivacy() {
    showModalBottomSheet<void>(
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
            ListTile(
              leading: const Icon(Icons.download_rounded,
                  color: AppColors.textPrimary),
              title: Text('Экспорт моих данных', style: AppTypography.body),
              subtitle: Text(
                'Скопируется JSON в буфер',
                style: AppTypography.caption.copyWith(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _exportData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.warning),
              title: Text('Удалить аккаунт',
                  style:
                      AppTypography.body.copyWith(color: AppColors.warning)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openSettingsCog() {
    showModalBottomSheet<void>(
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
            ListTile(
              leading: const Icon(Icons.refresh_rounded,
                  color: AppColors.textPrimary),
              title:
                  Text('Пройти анкету заново', style: AppTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                widget.onRetake();
              },
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined,
                  color: AppColors.textPrimary),
              title: Text('Показать туториал', style: AppTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (ctx2) => WelcomeTutorialScreen(
                      onFinish: () => Navigator.of(ctx2).pop(),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_rounded,
                  color: AppColors.textPrimary),
              title: Text('Политика конфиденциальности',
                  style: AppTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (ctx2) => LegalViewerScreen(
                      docKey: 'legal_privacy',
                      title: 'Политика конфиденциальности',
                      onBack: () => Navigator.of(ctx2).pop(),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.gavel_rounded,
                  color: AppColors.textPrimary),
              title: Text('Пользовательское соглашение',
                  style: AppTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (ctx2) => LegalViewerScreen(
                      docKey: 'legal_terms',
                      title: 'Пользовательское соглашение',
                      onBack: () => Navigator.of(ctx2).pop(),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.medical_information_outlined,
                  color: AppColors.textPrimary),
              title: Text('Медицинская оговорка',
                  style: AppTypography.body),
              subtitle: Text(
                'Лина — не врач. Информационно-справочный сервис.',
                style: AppTypography.caption,
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (ctx2) => LegalViewerScreen(
                      docKey: 'legal_medical',
                      title: 'Медицинская оговорка',
                      onBack: () => Navigator.of(ctx2).pop(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _exportData() async {
    try {
      final data = await ref.read(backendApiProvider).exportData();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Данные скопированы в буфер обмена')),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Удалить аккаунт?', style: AppTypography.h2),
        content: Text(
          'Это удалит профиль, рекомендации, отметки и полку. Действие необратимо.',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
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

  Future<String?> _pickTime({
    required String label,
    required String current,
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
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
  }

  String? _subtitle() {
    final type = _skinTypeLabel(_profile.skinType);
    if (type == null) return null;
    return type.toLowerCase() + ' кожа';
  }

  String? _skinTypeLabel(String? id) => switch (id) {
        'dry' => 'Сухая',
        'oily' => 'Жирная',
        'combo' => 'Комбинированная',
        'normal' => 'Нормальная',
        'sensitive' => 'Чувствительная',
        _ => null,
      };

  String _remindersDetail() {
    final n = _settings.notifications;
    if (!n.morning && !n.evening) return 'выкл';
    final parts = <String>[
      if (n.morning) 'Утро',
      if (n.evening) 'Вечер',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile.name?.trim().isNotEmpty == true
        ? _profile.name!.trim()
        : 'Без имени';
    final scoreText = widget.skinScore?.toString() ?? '—';
    final streakText = widget.streak?.toString() ?? '—';
    final shelfText = _shelfCount?.toString() ?? '—';
    final subtitle = _subtitle();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.blush)),
          SafeArea(
            child: ListView(
              padding:
                  const EdgeInsets.fromLTRB(0, 0, 0, AppSpacing.xxl),
              children: [
                _TopBar(onBack: widget.onBack, onSettings: _openSettingsCog),
                _AvatarBlock(
                  name: name,
                  subtitle: subtitle,
                  onEdit: _openAvatarSheet,
                  avatarUrl: ref
                      .read(backendApiProvider)
                      .avatarUrl(cacheBust: _avatarVersion),
                  headers:
                      ref.read(backendApiProvider).imageAuthHeaders(),
                ),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg),
                  child: _StatsCard(
                    index: scoreText,
                    streak: streakText,
                    shelf: shelfText,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _Group(
                  title: 'Моё',
                  children: [
                    _Row(
                      icon: Icons.bookmark_outline_rounded,
                      label: 'Моя полка',
                      detail: shelfText,
                      onTap: widget.onOpenShelf,
                    ),
                    _Row(
                      icon: Icons.trending_up_rounded,
                      label: 'Прогресс кожи',
                      onTap: widget.onOpenProgress,
                    ),
                    if (widget.onOpenRoutineHistory != null)
                      _Row(
                        icon: Icons.history_rounded,
                        label: 'История уходов',
                        onTap: widget.onOpenRoutineHistory,
                      ),
                    if (widget.onOpenFavorites != null)
                      _Row(
                        icon: Icons.favorite_outline_rounded,
                        label: 'Избранное',
                        onTap: widget.onOpenFavorites,
                      ),
                  ],
                ),
                _Group(
                  title: 'Лина — мой AI-агент',
                  children: [
                    _Row(
                      icon: Icons.spa_outlined,
                      label: 'Тип кожи',
                      detail: _skinTypeLabel(_profile.skinType) ?? '—',
                      onTap: _editSkinType,
                    ),
                    _Row(
                      icon: Icons.flag_outlined,
                      label: 'Цели и приоритеты',
                      detail: _profile.concerns.isEmpty
                          ? '—'
                          : _profile.concerns.length.toString(),
                      onTap: _editConcerns,
                    ),
                    _Row(
                      icon: Icons.notifications_outlined,
                      label: 'Напоминания',
                      detail: _remindersDetail(),
                      onTap: _openReminders,
                    ),
                  ],
                ),
                _Group(
                  title: 'Аккаунт',
                  children: [
                    _Row(
                      icon: Icons.shield_outlined,
                      label: 'Конфиденциальность',
                      onTap: _openPrivacy,
                    ),
                    _Row(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Перейти на Pro',
                      detail: 'скоро',
                      highlight: true,
                    ),
                    _Row(
                      icon: Icons.logout_rounded,
                      label: 'Выйти',
                      muted: true,
                      onTap: () => ref
                          .read(authControllerProvider.notifier)
                          .logout(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Text(
                    'MySkin · v0.1.0 · Made with ✿',
                    style: AppTypography.eyebrow(
                        color: AppColors.textSecondary),
                  ),
                ),
                if (!_loaded) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Center(
                    child: Text('Загружаем настройки…',
                        style: AppTypography.caption.copyWith(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onSettings});
  final VoidCallback onBack;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          _RoundButton(
              icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
          const Spacer(),
          _RoundButton(icon: Icons.settings_outlined, onTap: onSettings),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: Colors.white.withOpacity(0.7),
        shape: const CircleBorder(
            side: BorderSide(color: AppColors.divider)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _AvatarBlock extends StatelessWidget {
  const _AvatarBlock({
    required this.name,
    required this.subtitle,
    required this.onEdit,
    required this.avatarUrl,
    required this.headers,
  });

  final String name;
  final String? subtitle;
  final VoidCallback onEdit;
  final String avatarUrl;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '✿' : name.characters.first.toUpperCase();
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
                clipBehavior: Clip.antiAlias,
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
                      color: AppColors.primaryAccent.withOpacity(0.45),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                      spreadRadius: -10,
                    ),
                  ],
                ),
                child: Image.network(
                  avatarUrl,
                  headers: headers,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(
                      initial,
                      style: AppTypography.serifItalic(
                        fontSize: 40,
                        color: AppColors.roseDeep,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Material(
                  color: AppColors.roseDeep,
                  shape: const CircleBorder(
                      side: BorderSide(color: Colors.white, width: 2.5)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onEdit,
                    child: const SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(Icons.edit_rounded,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(name, style: AppTypography.h1.copyWith(fontSize: 26)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!,
              style: AppTypography.caption.copyWith(fontSize: 13)),
        ],
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.index,
    required this.streak,
    required this.shelf,
  });

  final String index;
  final String streak;
  final String shelf;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (value: index, label: 'Индекс'),
      (value: streak, label: 'Дней подряд'),
      (value: shelf, label: 'На полке'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++)
            Expanded(
              child: Container(
                decoration: i == 0
                    ? null
                    : const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: AppColors.divider),
                        ),
                      ),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Text(
                      stats[i].value,
                      style: AppTypography.h1.copyWith(
                        fontSize: 26,
                        color: AppColors.roseDeep,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stats[i].label,
                      style: AppTypography.caption.copyWith(fontSize: 11),
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

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final divided = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      divided.add(children[i]);
      if (i < children.length - 1) {
        divided.add(Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: AppColors.divider,
        ));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: EyebrowText(title, color: AppColors.textSecondary),
          ),
          // Border + rounded-corner clip applied here; rows inside paint their
          // own surface so InkWell ripples are visible on a real Material
          // ancestor instead of disappearing into a transparent parent.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.divider),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(children: divided),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.detail,
    this.onTap,
    this.highlight = false,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onTap;

  /// "Pro" — blush tint background, rose accents on icon + detail.
  final bool highlight;

  /// "Выйти" / destructive — warning colour text, no chevron.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final labelColor =
        muted ? AppColors.warning : AppColors.textPrimary;
    final iconBg = highlight
        ? AppColors.primary
        : (muted
            ? AppColors.warning.withOpacity(0.10)
            : const Color(0x0A2E2E2E));
    final iconColor = highlight
        ? AppColors.roseDeep
        : (muted ? AppColors.warning : AppColors.textPrimary);
    final detailColor =
        highlight ? AppColors.roseDeep : AppColors.textSecondary;
    return Material(
      // Each row paints its own surface — gives InkWell a real Material to
      // ink onto and makes the ripple visible. _Group only owns the rounded
      // border + clip.
      color: highlight
          ? AppColors.roseDeep.withOpacity(0.06)
          : AppColors.surface,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primaryAccent.withOpacity(0.15),
        highlightColor: AppColors.primaryAccent.withOpacity(0.06),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    fontSize: 15,
                    color: labelColor,
                  ),
                ),
              ),
              if (detail != null) ...[
                Text(
                  detail!,
                  style: AppTypography.bodySm.copyWith(
                    color: detailColor,
                    fontWeight:
                        highlight ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (!muted) const SizedBox(width: 8),
              ],
              if (!muted)
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConcernChip extends StatelessWidget {
  const _ConcernChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
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
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active ? AppColors.roseDeep : AppColors.dividerStrong,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.bodySm.copyWith(
              fontWeight: FontWeight.w500,
              color: active ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.time,
    required this.onEnabled,
    required this.onPickTime,
  });

  final IconData icon;
  final String title;
  final bool enabled;
  final String time;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  onTap: enabled ? onPickTime : null,
                  child: Text(
                    enabled ? time : 'выкл',
                    style: AppTypography.caption.copyWith(
                      color: enabled
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
            value: enabled,
            onChanged: onEnabled,
            activeColor: AppColors.roseDeep,
          ),
        ],
      ),
    );
  }
}
