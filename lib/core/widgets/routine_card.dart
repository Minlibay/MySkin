import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../../features/api/backend_api.dart';
import '../../features/catalog/domain/product.dart';
import 'app_card.dart';

class RoutineCard extends ConsumerWidget {
  const RoutineCard({
    super.key,
    required this.stepNumber,
    required this.title,
    required this.ingredients,
    required this.explanation,
    this.product,
    this.recommendation,
    this.onOpenProduct,
  });

  final int stepNumber;
  final String title;
  final List<String> ingredients;
  final String explanation;

  /// Bottle from the user's shelf that fulfils this step.
  final Product? product;

  /// Top catalog match sent by the backend when the shelf doesn't cover this
  /// step. Tapping it should open the product page where the user can buy.
  final Product? recommendation;

  /// Opens the product detail screen. When null the chip is not tappable.
  final ValueChanged<Product>? onOpenProduct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // When we have a real product (owned or recommended), the bottle takes
    // priority — the ingredient pill row is only useful when we have no
    // product to show.
    final showIngredients =
        product == null && recommendation == null && ingredients.isNotEmpty;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$stepNumber',
                  style: AppTypography.body.copyWith(
                    color: AppColors.primaryAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.body
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (showIngredients) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: ingredients
                  .map(
                    (i) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(i, style: AppTypography.caption),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (product != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _RoutineProductChip(
              product: product!,
              isOwned: true,
              onTap: onOpenProduct == null
                  ? null
                  : () => onOpenProduct!(product!),
            ),
          ] else if (recommendation != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _RoutineProductChip(
              product: recommendation!,
              isOwned: false,
              onTap: onOpenProduct == null
                  ? null
                  : () => onOpenProduct!(recommendation!),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(explanation, style: AppTypography.bodySecondary),
        ],
      ),
    );
  }
}

/// Inline product card embedded under a routine step. Mirrors the chip used
/// on the Ritual screen — owned bottles get a soft "С полки" label, catalog
/// recommendations get a primary "Купить" pill that opens the product page.
class _RoutineProductChip extends ConsumerWidget {
  const _RoutineProductChip({
    required this.product,
    required this.isOwned,
    this.onTap,
  });

  final Product product;
  final bool isOwned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(backendApiProvider);
    final photoUrl = product.hasPhoto
        ? (product.isCustom
            ? api.customProductPhotoUrl(product.id)
            : api.productPhotoUrl(product.id))
        : null;
    return Material(
      color: Colors.white.withOpacity(0.85),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isOwned
              ? AppColors.primaryAccent.withOpacity(0.4)
              : AppColors.divider,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 56,
                  child: photoUrl != null
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _BottleFallback(color: product.accentColor),
                        )
                      : _BottleFallback(color: product.accentColor),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isOwned ? 'С ПОЛКИ' : 'РЕКОМЕНДУЕТ ЛИНА',
                      style: AppTypography.eyebrow(color: AppColors.roseDeep)
                          .copyWith(fontSize: 9),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.brand,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (!isOwned && product.priceRub > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${product.priceRub} ₽',
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (!isOwned)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.roseDeep,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Купить',
                    style: AppTypography.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottleFallback extends StatelessWidget {
  const _BottleFallback({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, color],
        ),
      ),
    );
  }
}
