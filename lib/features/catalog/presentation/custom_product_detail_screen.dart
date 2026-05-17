import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';
import '../../chat/presentation/chat_controller.dart';
import '../domain/product.dart';
import 'product_bottle.dart';

/// Detail page for a user-added (custom) shelf product. Catalog products
/// open `ProductDetailScreen` instead — that path needs slug-based fetch,
/// telemetry, buy URL, favourites; none of which apply here.
class CustomProductDetailScreen extends ConsumerStatefulWidget {
  const CustomProductDetailScreen({
    super.key,
    required this.product,
    required this.onBack,
    required this.onAskLina,
    required this.onDeleted,
  });

  final Product product;
  final VoidCallback onBack;
  final VoidCallback onAskLina;
  final VoidCallback onDeleted;

  @override
  ConsumerState<CustomProductDetailScreen> createState() =>
      _CustomProductDetailScreenState();
}

class _CustomProductDetailScreenState
    extends ConsumerState<CustomProductDetailScreen> {
  bool _busy = false;

  Future<void> _askLina() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Compose a structured question. Лина already sees the user's profile
    // server-side via /ai/chat, so we only need to describe the product.
    final p = widget.product;
    final lines = <String>[
      'Подскажи, подходит ли мне это средство:',
      '— Бренд: ${p.brand}',
      '— Название: ${p.name}',
      '— Категория: ${p.kindLabel}',
    ];
    final exp = p.effectiveExpiry;
    if (exp != null) {
      final days = exp.difference(DateTime.now()).inDays;
      if (days < 0) {
        lines.add('— Срок годности истёк ${(-days)} дн. назад.');
      } else if (days <= 30) {
        lines.add('— Срок истекает через $days дн.');
      }
    }
    if (p.fillLevel == 'empty') {
      lines.add('— Уровень в банке: закончилось.');
    } else if (p.fillLevel == 'low') {
      lines.add('— Уровень в банке: заканчивается.');
    }
    final prompt = lines.join('\n');
    widget.onAskLina();
    // Fire-and-forget — chat screen subscribes to the same provider.
    ref.read(chatControllerProvider.notifier).send(prompt);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить с полки?'),
        content: Text(
            'Это убирает «${widget.product.brand} ${widget.product.name}» только у тебя.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(backendApiProvider)
          .removeCustomProduct(widget.product.id);
      if (!mounted) return;
      widget.onDeleted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не получилось: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.champagne)),
          SafeArea(
            child: Column(
              children: [
                _Header(brand: p.brand, onBack: widget.onBack),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0,
                        AppSpacing.lg, AppSpacing.xxl),
                    children: [
                      Center(
                        child: ProductBottle(
                          product: p,
                          width: 120,
                          height: 180,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(p.name,
                          textAlign: TextAlign.center,
                          style: AppTypography.h1.copyWith(fontSize: 24)),
                      const SizedBox(height: 4),
                      Text(p.kindLabel,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySecondary),
                      const SizedBox(height: AppSpacing.lg),
                      _FactsCard(product: p),
                      const SizedBox(height: AppSpacing.lg),
                      AppButton(
                        label: 'Спросить Лину, подходит ли мне',
                        onPressed: _busy ? null : _askLina,
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _busy ? null : _delete,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.warning,
                        ),
                        child: const Text('Удалить с полки'),
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
}

class _Header extends StatelessWidget {
  const _Header({required this.brand, required this.onBack});
  final String brand;
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
            child: EyebrowText(brand, color: AppColors.roseDeep),
          ),
        ],
      ),
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    final fillLabel = switch (product.fillLevel) {
      'full' => 'Полный',
      'half' => 'Половина',
      'low' => 'Заканчивается',
      'empty' => 'Закончился',
      _ => null,
    };
    if (fillLabel != null) {
      rows.add(_row('Уровень', fillLabel));
    }
    if (product.openedAt != null) {
      rows.add(_row('Открыто', _fmtDate(product.openedAt!)));
    }
    if (product.paoMonths != null) {
      rows.add(_row('PAO', '${product.paoMonths} мес.'));
    }
    if (product.expiresAt != null) {
      rows.add(_row('Годен до', _fmtDate(product.expiresAt!)));
    }
    final eff = product.effectiveExpiry;
    if (eff != null) {
      final status = product.expiryStatus;
      final days = eff.difference(DateTime.now()).inDays;
      final tone = switch (status) {
        'expired' => const Color(0xFFB3261E),
        'expiring_soon' => const Color(0xFFB07000),
        _ => AppColors.textPrimary,
      };
      final text = days < 0
          ? 'Истёк ${-days} дн. назад'
          : days == 0
              ? 'Истекает сегодня'
              : 'Осталось $days дн.';
      rows.add(_row('Состояние', text, valueColor: tone));
    }

    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: rows),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
                child: Text(label, style: AppTypography.bodySecondary)),
            Text(
              value,
              style: AppTypography.body.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';
}
