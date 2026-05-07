import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';
import '../domain/product.dart';
import 'product_bottle.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({
    super.key,
    required this.onOpen,
    required this.onBack,
  });
  final void Function(Product) onOpen;
  final VoidCallback onBack;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String? _kind;
  String? _concern;
  late Future<List<Product>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Product>> _load() {
    return ref.read(backendApiProvider).listCatalog(
          kind: _kind,
          concern: _concern,
        );
  }

  void _refresh() {
    setState(() => _future = _load());
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
                _Filters(
                  kind: _kind,
                  concern: _concern,
                  onKind: (v) {
                    setState(() => _kind = v);
                    _refresh();
                  },
                  onConcern: (v) {
                    setState(() => _concern = v);
                    _refresh();
                  },
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
                      if (snap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Text(
                              'Не удалось загрузить каталог.\n${snap.error}',
                              style: AppTypography.bodySecondary,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      final items = snap.data ?? const [];
                      if (items.isEmpty) {
                        return Center(
                          child: Text('Ничего не нашли',
                              style: AppTypography.bodySecondary),
                        );
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.xxl),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.62,
                        ),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _ProductCard(
                          product: items[i],
                          onTap: () => widget.onOpen(items[i]),
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
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EyebrowText('Каталог', color: AppColors.roseDeep),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'Подобрано ',
                        style: AppTypography.h1.copyWith(fontSize: 26)),
                    TextSpan(
                      text: 'тебе',
                      style: AppTypography.serifItalic(fontSize: 26),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.kind,
    required this.concern,
    required this.onKind,
    required this.onConcern,
  });

  final String? kind;
  final String? concern;
  final ValueChanged<String?> onKind;
  final ValueChanged<String?> onConcern;

  static const _kinds = [
    ('cleanser', 'Очищение'),
    ('serum', 'Сыворотка'),
    ('moisturizer', 'Крем'),
    ('spf', 'SPF'),
    ('essence', 'Эссенция'),
  ];

  static const _concerns = [
    ('acne', 'Акне'),
    ('pih', 'Постакне'),
    ('aging', 'Anti-age'),
    ('dullness', 'Сияние'),
    ('redness', 'Покраснения'),
    ('dehydration', 'Увлажнение'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 4, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChipRow(
            options: _kinds,
            selected: kind,
            onSelect: onKind,
          ),
          const SizedBox(height: 8),
          _ChipRow(
            options: _concerns,
            selected: concern,
            onSelect: onConcern,
          ),
        ],
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<(String, String)> options;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          AppChip(
            label: 'Все',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: 6),
          for (final o in options) ...[
            AppChip(
              label: o.$2,
              selected: selected == o.$1,
              onTap: () => onSelect(selected == o.$1 ? null : o.$1),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.matchScore != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 11, color: AppColors.roseDeep),
                      const SizedBox(width: 4),
                      Text(
                        '${product.matchScore}% совпадение',
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.roseDeep,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Center(
                child: ProductBottle(
                  product: product,
                  width: 56,
                  height: 84,
                  label: product.kindLabel,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                product.brand,
                style: AppTypography.eyebrow().copyWith(fontSize: 10),
              ),
              const SizedBox(height: 2),
              Text(
                product.name,
                style: AppTypography.h3.copyWith(fontSize: 15, height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                '${product.priceRub} ₽',
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
