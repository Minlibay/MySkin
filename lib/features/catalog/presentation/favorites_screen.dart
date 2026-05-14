import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback_state.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';
import '../domain/product.dart';
import 'product_bottle.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({
    super.key,
    required this.onBack,
    required this.onOpen,
  });

  final VoidCallback onBack;
  final ValueChanged<Product> onOpen;

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  late Future<List<Product>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(backendApiProvider).listFavorites();
  }

  Future<void> _reload() async {
    setState(() {
      _future = ref.read(backendApiProvider).listFavorites();
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
                _Header(onBack: widget.onBack),
                Expanded(
                  child: FutureBuilder<List<Product>>(
                    future: _future,
                    builder: (_, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return FeedbackState.loading();
                      }
                      if (snap.hasError) {
                        return FeedbackState.error(onRetry: _reload);
                      }
                      final items = snap.data ?? const [];
                      if (items.isEmpty) {
                        return FeedbackState.empty(
                          icon: Icons.favorite_border_rounded,
                          title: 'Тут пока пусто',
                          body:
                              'Лайкни товар на карточке — он появится здесь.',
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: _reload,
                        color: AppColors.primaryAccent,
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.xxl,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.62,
                          ),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _FavCard(
                            product: items[i],
                            onTap: () => widget.onOpen(items[i]),
                          ),
                        ),
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
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: AppColors.textPrimary,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(child: Text('Избранное', style: AppTypography.h1)),
        ],
      ),
    );
  }
}

class _FavCard extends StatelessWidget {
  const _FavCard({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: Hero(
                    tag: 'bottle-${product.slug}',
                    child: ProductBottle(
                      product: product,
                      width: 70,
                      height: 110,
                      label: product.kindLabel,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.brand,
                style: AppTypography.eyebrow(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                product.name,
                style: AppTypography.bodyMedium.copyWith(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
