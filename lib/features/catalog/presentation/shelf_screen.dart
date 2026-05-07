import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';
import '../domain/product.dart';
import 'product_bottle.dart';

class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({
    super.key,
    required this.onOpen,
    required this.onBack,
  });
  final void Function(Product) onOpen;
  final VoidCallback onBack;

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  late Future<List<Product>> _future;
  String? _filter; // null = all, else 'have' | 'wishlist' | 'finished'

  @override
  void initState() {
    super.initState();
    _future = ref.read(backendApiProvider).getShelf();
  }

  Future<void> _remove(Product p) async {
    try {
      await ref.read(backendApiProvider).removeFromShelf(p.id);
      if (!mounted) return;
      setState(() {
        _future = ref.read(backendApiProvider).getShelf();
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
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<Product>>(
                    future: _future,
                    builder: (_, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primaryAccent));
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
                      Text(
                        product.brand,
                        style: AppTypography.eyebrow().copyWith(fontSize: 10),
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
                        '${product.kindLabel} · ${product.priceRub} ₽',
                        style: AppTypography.caption.copyWith(fontSize: 12),
                      ),
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
