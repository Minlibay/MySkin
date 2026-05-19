import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/feedback_state.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';
import '../../notifications/data/local_notifications.dart';
import '../domain/product.dart';
import 'product_bottle.dart';

class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({
    super.key,
    required this.onOpen,
    required this.onBack,
    required this.onAddCustom,
  });
  final void Function(Product) onOpen;
  final VoidCallback onBack;
  final VoidCallback onAddCustom;

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  late Future<List<Product>> _future;
  String? _filter; // null = all, else 'have' | 'wishlist' | 'finished'

  @override
  void initState() {
    super.initState();
    _future = ref.read(backendApiProvider).getShelf().then((items) {
      _scheduleExpiryReminders(items);
      return items;
    });
  }

  void _scheduleExpiryReminders(List<Product> items) {
    // Fire-and-forget: a failed reschedule shouldn't block rendering.
    ref
        .read(localNotificationsProvider)
        .rescheduleExpiryReminders<Product>(
          items: items.where((p) => p.effectiveExpiry != null),
          keyOf: (p) => p.id,
          labelOf: (p) => '${p.brand} ${p.name}',
          expiryOf: (p) => p.effectiveExpiry,
        );
  }

  Future<void> _buildRoutine() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final preview =
          await ref.read(backendApiProvider).buildRoutineFromShelf(
                preview: true,
              );
      final payload = (preview['payload'] as Map).cast<String, dynamic>();
      if (!mounted) return;
      final shouldSave = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (_) => _RoutinePreviewSheet(payload: payload),
          ) ??
          false;
      if (!shouldSave) return;
      await ref.read(backendApiProvider).buildRoutineFromShelf();
      messenger.showSnackBar(
        const SnackBar(content: Text('Рутина сохранена')),
      );
    } on EmptyShelfException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _remove(Product p) async {
    try {
      await ref.read(backendApiProvider).removeFromShelf(p.id);
      if (!mounted) return;
      setState(() {
        _future = ref.read(backendApiProvider).getShelf().then((items) {
          _scheduleExpiryReminders(items);
          return items;
        });
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.roseDeep,
        foregroundColor: Colors.white,
        onPressed: widget.onAddCustom,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(
          'Добавить своё',
          style: AppTypography.bodySm
              .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.champagne)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
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
                            onTap: widget.onBack,
                            child: const Icon(Icons.arrow_back_ios_new,
                                size: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const EyebrowText('Моя полка',
                                color: AppColors.roseDeep),
                            const SizedBox(height: 2),
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                    text: 'Мои ',
                                    style: AppTypography.h1
                                        .copyWith(fontSize: 26)),
                                TextSpan(
                                  text: 'продукты',
                                  style:
                                      AppTypography.serifItalic(fontSize: 26),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ),
                      _BuildRoutineButton(onTap: _buildRoutine),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<Product>>(
                    future: _future,
                    builder: (_, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return FeedbackState.loading();
                      }
                      if (snap.hasError) {
                        return FeedbackState.error(
                          onRetry: () => setState(() {
                            _future = ref
                                .read(backendApiProvider)
                                .getShelf()
                                .then((items) {
                              _scheduleExpiryReminders(items);
                              return items;
                            });
                          }),
                        );
                      }
                      final all = snap.data ?? const [];
                      if (all.isEmpty) {
                        return _Empty();
                      }
                      final items = _filter == null
                          ? all
                          : all
                              .where((p) => p.shelfStatus == _filter)
                              .toList();
                      return Column(
                        children: [
                          _StatusFilters(
                            counts: _counts(all),
                            selected: _filter,
                            onSelect: (s) =>
                                setState(() => _filter = s),
                          ),
                          Expanded(
                            child: items.isEmpty
                                ? Center(
                                    child: Text(
                                      'В этой группе пока пусто',
                                      style: AppTypography.bodySecondary,
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.lg,
                                        AppSpacing.sm,
                                        AppSpacing.lg,
                                        AppSpacing.xxl),
                                    itemCount: items.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (_, i) => _ShelfRow(
                                      product: items[i],
                                      onTap: () =>
                                          widget.onOpen(items[i]),
                                      onRemove: () =>
                                          _remove(items[i]),
                                    ),
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, int> _counts(List<Product> all) {
    final m = <String, int>{};
    for (final p in all) {
      final s = p.shelfStatus ?? 'have';
      m[s] = (m[s] ?? 0) + 1;
    }
    return m;
  }
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final Map<String, int> counts;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Row(
        children: [
          _Chip(
            label: 'Все',
            count: total,
            active: selected == null,
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: 6),
          _Chip(
            label: 'Использую',
            count: counts['have'] ?? 0,
            active: selected == 'have',
            onTap: () => onSelect('have'),
          ),
          const SizedBox(width: 6),
          _Chip(
            label: 'Хочу',
            count: counts['wishlist'] ?? 0,
            active: selected == 'wishlist',
            onTap: () => onSelect('wishlist'),
          ),
          const SizedBox(width: 6),
          _Chip(
            label: 'Закончилось',
            count: counts['finished'] ?? 0,
            active: selected == 'finished',
            onTap: () => onSelect('finished'),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: active ? AppColors.roseDeep : AppColors.surface,
            border: Border.all(
              color: active
                  ? AppColors.roseDeep
                  : AppColors.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.bodySm.copyWith(
                  fontSize: 13,
                  color: active ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withOpacity(0.25)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color:
                        active ? Colors.white : AppColors.roseDeep,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.product,
    required this.onTap,
    required this.onRemove,
  });
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(product.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppColors.warning),
      ),
      onDismissed: (_) => onRemove(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                ProductBottle(
                  product: product,
                  width: 50,
                  height: 70,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              product.brand,
                              style: AppTypography.eyebrow()
                                  .copyWith(fontSize: 10),
                            ),
                          ),
                          if (product.isCustom) const _CustomBadge(),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        product.name,
                        style: AppTypography.h3
                            .copyWith(fontSize: 15, height: 1.2),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        product.isCustom
                            ? product.kindLabel
                            : '${product.kindLabel} · ${product.priceRub} ₽',
                        style: AppTypography.caption.copyWith(fontSize: 12),
                      ),
                      if (product.expiryStatus != null) ...[
                        const SizedBox(height: 6),
                        _ExpiryBadge(product: product),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomBadge extends StatelessWidget {
  const _CustomBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.roseDeep.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'Моё',
        style: AppTypography.caption.copyWith(
          fontSize: 9,
          color: AppColors.roseDeep,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ExpiryBadge extends StatelessWidget {
  const _ExpiryBadge({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final status = product.expiryStatus;
    final exp = product.effectiveExpiry;
    if (status == null || exp == null) return const SizedBox.shrink();

    final (label, fg, bg, icon) = switch (status) {
      'expired' => (
        _expiredLabel(exp),
        const Color(0xFFB3261E),
        const Color(0xFFB3261E).withOpacity(0.12),
        Icons.warning_amber_rounded,
      ),
      'expiring_soon' => (
        _untilLabel(exp),
        const Color(0xFFB07000),
        const Color(0xFFFFC107).withOpacity(0.18),
        Icons.schedule_rounded,
      ),
      _ => (
        _untilLabel(exp),
        AppColors.textSecondary,
        AppColors.divider,
        Icons.event_available_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              fontSize: 11,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static String _untilLabel(DateTime exp) {
    final days = exp.difference(DateTime.now()).inDays;
    if (days <= 0) return 'Истекает сегодня';
    if (days == 1) return 'Истекает завтра';
    if (days < 30) return 'Истекает через $days дн.';
    final months = (days / 30).round();
    return 'Истекает через $months мес.';
  }

  static String _expiredLabel(DateTime exp) {
    final days = DateTime.now().difference(exp).inDays;
    if (days <= 0) return 'Срок истёк';
    if (days < 30) return 'Истёк $days дн. назад';
    final months = (days / 30).round();
    return 'Истёк $months мес. назад';
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🌷', style: TextStyle(fontSize: 56)),
          const SizedBox(height: AppSpacing.md),
          Text('Полка пуста',
              style: AppTypography.h2, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Открой каталог и добавь первое средство — будем следить вместе.',
            style: AppTypography.bodySecondary,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Compact icon button in the shelf header — generates a routine from the
/// products on the shelf. Visually muted so it doesn't compete with the
/// primary "add custom" FAB.
class _BuildRoutineButton extends StatelessWidget {
  const _BuildRoutineButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Material(
        color: AppColors.primaryAccent.withOpacity(0.14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.roseDeep.withOpacity(0.18))),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 16, color: AppColors.roseDeep),
                const SizedBox(width: 6),
                Text(
                  'Рутина',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.roseDeep,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that shows the morning + evening lists built from shelf
/// products, ordered by canonical step sequence. The user either confirms
/// (saves to /me/routines) or cancels.
class _RoutinePreviewSheet extends StatelessWidget {
  const _RoutinePreviewSheet({required this.payload});
  final Map<String, dynamic> payload;

  static const _kindLabel = {
    'cleanser': 'Очищение',
    'scrub': 'Скраб',
    'peeling': 'Пилинг',
    'toner': 'Тоник',
    'pad': 'Пэды',
    'essence': 'Эссенция',
    'mask': 'Маска',
    'eye_patch': 'Патчи для глаз',
    'serum': 'Сыворотка',
    'eye_serum': 'Сыворотка для глаз',
    'eye_cream': 'Крем для глаз',
    'moisturizer': 'Крем',
    'spf': 'SPF',
  };

  @override
  Widget build(BuildContext context) {
    final morning = ((payload['morning'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final evening = ((payload['evening'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Рутина из твоей полки',
                style: AppTypography.h2.copyWith(fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              'Собрано из средств, помеченных «Использую». Можно сохранить '
              'и пользоваться в разделе «Сегодня».',
              style: AppTypography.bodySm.copyWith(
                  color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            _phaseBlock('☀  Утро', morning),
            const SizedBox(height: AppSpacing.md),
            _phaseBlock('☾  Вечер', evening),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.roseDeep,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: morning.isEmpty && evening.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(true),
                    child: const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _phaseBlock(String title, List<Map<String, dynamic>> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EyebrowText(title, color: AppColors.roseDeep),
        const SizedBox(height: 6),
        if (steps.isEmpty)
          Text(
            'Здесь пока пусто — добавь средства на полку.',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.textSecondary),
          )
        else
          ...steps.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.roseDeep,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text:
                                  '${_kindLabel[s['kind']] ?? s['kind']} · ',
                              style: AppTypography.bodySm.copyWith(
                                  color: AppColors.textSecondary)),
                          TextSpan(
                            text: '${s['brand']} ${s['name']}',
                            style: AppTypography.bodySm
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}
