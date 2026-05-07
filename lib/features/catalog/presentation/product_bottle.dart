import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../api/backend_api.dart';
import '../domain/product.dart';

/// Either a real product photo (from backend) or stylised illustration
/// using the product's accent color when no photo is uploaded.
class ProductBottle extends ConsumerWidget {
  const ProductBottle({
    super.key,
    required this.product,
    this.width = 56,
    this.height = 80,
    this.label,
  });

  final Product product;
  final double width;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (product.hasPhoto) {
      final api = ref.watch(backendApiProvider);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          height: height,
          child: Image.network(
            api.productPhotoUrl(product.id),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _illustration(),
          ),
        ),
      );
    }
    return _illustration();
  }

  Widget _illustration() {
    final cap = product.kind == 'spf' ? Colors.black87 : AppColors.roseDeep;
    final liquid = product.accentColor;
    return SizedBox(
      width: width,
      height: height + 6,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // cap
          Positioned(
            top: 0,
            child: Container(
              width: width * 0.36,
              height: 12,
              decoration: BoxDecoration(
                color: cap,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                  bottom: Radius.circular(2),
                ),
              ),
            ),
          ),
          // bottle body
          Positioned(
            top: 10,
            child: Container(
              width: width,
              height: height - 4,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, AppColors.primary],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                  bottom: Radius.circular(4),
                ),
                border: Border.all(
                    color: AppColors.primaryAccent.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: liquid.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                    spreadRadius: -4,
                  ),
                ],
              ),
            ),
          ),
          // liquid
          Positioned(
            top: 10 + (height - 4) * 0.3,
            left: width * 0.12,
            right: width * 0.12,
            height: (height - 4) * 0.55,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    liquid.withOpacity(0.85),
                    liquid.withOpacity(0.55),
                  ],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // label
          if (label != null)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Text(
                label!.toUpperCase(),
                textAlign: TextAlign.center,
                style: AppTypography.eyebrow().copyWith(fontSize: 7),
              ),
            ),
        ],
      ),
    );
  }
}
