import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../../core/widgets/metric_ring.dart';
import '../../../core/widgets/pill.dart';
import '../../api/backend_api.dart';
import '../domain/product.dart';
import 'product_bottle.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.slug,
    required this.onBack,
  });
  final String slug;
  final VoidCallback onBack;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  late Future<Product> _future;
  bool _addingToShelf = false;
  bool _onShelf = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(backendApiProvider).getProduct(widget.slug);
  }

  Future<void> _addToShelf(Product p) async {
    setState(() => _addingToShelf = true);
    try {
      await ref.read(backendApiProvider).addToShelf(productId: p.id);
      if (!mounted) return;
      setState(() => _onShelf = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавлено на полку')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _addingToShelf = false);
    }
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
            child: FutureBuilder<Product>(
              future: _future,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primaryAccent));
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Не удалось загрузить.\n${snap.error}',
                        style: AppTypography.bodySecondary,
                        textAlign: TextAlign.center),
                  );
                }
                final p = snap.data!;
                return _Body(
                  product: p,
                  onBack: widget.onBack,
                  onAdd: _addingToShelf || _onShelf
                      ? null
                      : () => _addToShelf(p),
                  addingToShelf: _addingToShelf,
                  onShelf: _onShelf,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.product,
    required this.onBack,
    required this.onAdd,
    required this.addingToShelf,
    required this.onShelf,
  });

  final Product product;
  final VoidCallback onBack;
  final VoidCallback? onAdd;
  final bool addingToShelf;
  final bool onShelf;

  @override
  Widget build(BuildContext context) {
    return Column(
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
                    onTap: onBack,
                    child: const Icon(Icons.arrow_back_ios_new, size: 16),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 110),
            children: [
              Center(
                child: Hero(
                  tag: 'bottle-${product.slug}',
                  child: ProductBottle(
                    product: product,
                    width: 100,
                    height: 160,
                    label: product.kindLabel,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: EyebrowText(product.brand,
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Text(
                product.name,
                style: AppTypography.h1,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${product.priceRub} ₽ · ${product.kindLabel}',
                  style: AppTypography.caption,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (product.matchScore != null)
                _MatchCard(
                  score: product.matchScore!,
                  reasons: product.matchReasons,
                ),
              const SizedBox(height: AppSpacing.md),
              _Section(
                title: 'О продукте',
                child: Text(product.description, style: AppTypography.body),
              ),
              if (product.ingredients.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Активные ингредиенты',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: product.ingredients
                        .map((i) => Pill(
                              label: i,
                              variant: PillVariant.outline,
                            ))
                        .toList(),
                  ),
                ),
              ],
              if (product.tags.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Помогает с',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: product.tags
                        .map((t) => Pill(
                              label: _concernLabel(t),
                              variant: PillVariant.soft,
                            ))
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _Section(
                title: 'Когда применять',
                child: Row(
                  children: [
                    Pill(
                      label: switch (product.routinePhase) {
                        'morning' => 'Утром',
                        'evening' => 'Вечером',
                        _ => 'Утром или вечером',
                      },
                      variant: PillVariant.dark,
                      icon: switch (product.routinePhase) {
                        'morning' => Icons.wb_sunny_rounded,
                        'evening' => Icons.nightlight_round,
                        _ => Icons.access_time_rounded,
                      },
                    ),
                    const SizedBox(width: 8),
                    if (product.isActive)
                      const Pill(
                        label: 'Актив',
                        variant: PillVariant.warning,
                      ),
                    if (product.gentle)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Pill(
                          label: 'Деликатно',
                          variant: PillVariant.success,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
          child: AppButton(
            label: onShelf ? 'На полке' : 'Добавить на полку',
            icon: onShelf ? Icons.check_rounded : Icons.add_rounded,
            onPressed: onAdd,
            loading: addingToShelf,
            variant:
                onShelf ? AppButtonVariant.soft : AppButtonVariant.accent,
          ),
        ),
      ],
    );
  }

  static String _concernLabel(String id) => switch (id) {
        'acne' => 'Акне',
        'pih' => 'Постакне',
        'aging' => 'Anti-age',
        'dullness' => 'Тусклость',
        'redness' => 'Покраснения',
        'dehydration' => 'Обезвоженность',
        _ => id,
      };
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.score, required this.reasons});
  final int score;
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final color = score >= 75
        ? AppColors.success
        : (score >= 55 ? AppColors.primaryAccent : AppColors.warning);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryAccent.withOpacity(0.18)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, AppColors.primary],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetricRing(
            value: score,
            size: 78,
            color: color,
            suffix: null,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EyebrowText('Совпадение', color: AppColors.roseDeep),
                const SizedBox(height: 4),
                Text(
                  _label(score),
                  style: AppTypography.h3.copyWith(color: color),
                ),
                const SizedBox(height: 6),
                ...reasons.map((r) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $r',
                          style: AppTypography.bodySm
                              .copyWith(fontSize: 13)),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _label(int s) {
    if (s >= 80) return 'Отлично подходит';
    if (s >= 65) return 'Хорошо подходит';
    if (s >= 50) return 'Средне подходит';
    return 'Можно лучше';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EyebrowText(title),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
