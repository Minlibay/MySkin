import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/glow_background.dart';
import '../data/notifications_controller.dart';
import '../domain/app_notification.dart';

/// Inbox of in-app notifications.
/// Tapping a row marks it read; "Прочитать все" clears every unread row.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.onBack,
    this.onOpenScan,
    this.onOpenRitual,
  });

  final VoidCallback onBack;
  final void Function(String scanId)? onOpenScan;
  final VoidCallback? onOpenRitual;

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsControllerProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(notificationsControllerProvider);
    final ctrl = ref.read(notificationsControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: GlowBackground(variant: GlowVariant.blush),
          ),
          SafeArea(
            child: Column(
              children: [
                _Header(
                  unread: s.unreadCount,
                  onBack: widget.onBack,
                  onMarkAll: s.unreadCount > 0 ? ctrl.markAllRead : null,
                ),
                Expanded(child: _body(s, ctrl)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(NotificationsState s, NotificationsController ctrl) {
    if (s.loading && !s.loadedOnce) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.error != null && s.items.isEmpty) {
      return _Centered(
        icon: Icons.cloud_off_rounded,
        title: 'Не удалось загрузить',
        body: s.error!,
        action: ('Повторить', ctrl.refresh),
      );
    }
    if (s.items.isEmpty) {
      return const _Centered(
        icon: Icons.notifications_none_rounded,
        title: 'Пока тихо',
        body: 'Сюда придут результаты анализов и напоминания о ритуале.',
      );
    }
    return RefreshIndicator(
      onRefresh: ctrl.refresh,
      color: AppColors.primaryAccent,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        itemCount: s.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, i) {
          final n = s.items[i];
          return _NotificationTile(
            notification: n,
            onTap: () => _onTap(n, ctrl),
          );
        },
      ),
    );
  }

  void _onTap(AppNotification n, NotificationsController ctrl) {
    if (n.isUnread) ctrl.markRead(n.id);
    switch (n.kind) {
      case 'scan_ready':
        final id = n.payload['scan_id'] as String?;
        if (id != null && widget.onOpenScan != null) widget.onOpenScan!(id);
      case 'ritual_morning':
      case 'ritual_evening':
        widget.onOpenRitual?.call();
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.unread,
    required this.onBack,
    required this.onMarkAll,
  });

  final int unread;
  final VoidCallback onBack;
  final VoidCallback? onMarkAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: AppColors.textPrimary,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Уведомления', style: AppTypography.h1),
                if (unread > 0)
                  Text(
                    'Непрочитанных: $unread',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.roseDeep,
                    ),
                  ),
              ],
            ),
          ),
          if (onMarkAll != null)
            TextButton(
              onPressed: onMarkAll,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.roseDeep,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: const Text('Прочитать все'),
            ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = notification.isUnread;
    return Material(
      color: unread ? AppColors.surface : AppColors.surface.withOpacity(0.55),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: unread ? AppColors.dividerStrong : AppColors.divider,
            ),
            boxShadow: unread
                ? const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KindIcon(kind: notification.kind),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: AppTypography.bodyMedium.copyWith(
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            margin: const EdgeInsets.only(
                                left: AppSpacing.xs, top: 6),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryAccent,
                            ),
                          ),
                      ],
                    ),
                    if (notification.body != null &&
                        notification.body!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        notification.body!,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _relative(notification.createdAt),
                      style: AppTypography.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (kind) {
      'scan_ready' => (Icons.favorite_rounded, AppColors.primaryAccent),
      'ritual_morning' => (Icons.wb_sunny_rounded, AppColors.gold),
      'ritual_evening' => (Icons.nightlight_round, AppColors.roseDeep),
      'product_new' => (Icons.local_florist_rounded, AppColors.sage),
      'lina_message' => (Icons.auto_awesome_rounded, AppColors.primaryAccent),
      _ => (Icons.notifications_rounded, AppColors.textSecondary),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.blush,
              ),
              child:
                  Icon(icon, size: 32, color: AppColors.primaryAccent),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: AppTypography.h2, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              style: AppTypography.bodySecondary,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: action!.$2,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.roseDeep,
                ),
                child: Text(action!.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _relative(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'только что';
  if (d.inMinutes < 60) return '${d.inMinutes} мин назад';
  if (d.inHours < 24) return '${d.inHours} ч назад';
  if (d.inDays < 7) return '${d.inDays} дн назад';
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}
