import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/feedback_state.dart';
import '../../../core/widgets/glow_background.dart';
import '../../../core/telemetry/product_telemetry.dart';
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
  bool? _favourite; // null until the loaded product seeds the initial state
  bool _expandedInci = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(backendApiProvider).getProduct(widget.slug).then((p) {
      // Seed favourite state from the server response once.
      if (mounted) setState(() => _favourite ??= p.isFavorite);
      // Detail open is the strongest signal a partner has — fire impression
      // + open the moment we have the resolved product id. Surfaces as
      // product_detail so it's distinguishable from a catalog tap-through.
      ref
          .read(productTelemetryProvider)
          .open(p.id, ProductSurface.productDetail);
      return p;
    });
  }

  Future<void> _toggleFavourite(Product p) async {
    final next = !(_favourite ?? p.isFavorite);
    setState(() => _favourite = next);
    final api = ref.read(backendApiProvider);
    try {
      if (next) {
        await api.addFavorite(p.id);
      } else {
        await api.removeFavorite(p.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _favourite = !next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не получилось сохранить: $e')),
      );
    }
  }

  Future<void> _openBuyUrl(Product p) async {
    final raw = p.buyUrl;
    if (raw == null || raw.isEmpty) return;
    // Fire buy_click before launching — leaving the app pauses the timer
    // queue, so we flush right after to make sure the partner sees the
    // event even if the user never comes back.
    final telemetry = ref.read(productTelemetryProvider);
    telemetry.buyClick(p.id, ProductSurface.productDetail);
    await telemetry.flush();
    final uri = Uri.tryParse(raw);
    if (uri == null || !await canLaunchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _addToShelf(Product p) async {
    setState(() => _addingToShelf = true);
    try {
      await ref.read(backendApiProvider).addToShelf(productId: p.id);
      ref
          .read(productTelemetryProvider)
          .shelfAdd(p.id, ProductSurface.productDetail);
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
                  return FeedbackState.loading();
                }
                if (snap.hasError) {
                  return FeedbackState.error(
                    onRetry: () => setState(() {
                      _future = ref
                          .read(backendApiProvider)
                          .getProduct(widget.slug);
                    }),
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
                  onBuy: (p.buyUrl != null && p.buyUrl!.isNotEmpty)
                      ? () => _openBuyUrl(p)
                      : null,
                  favourite: _favourite ?? p.isFavorite,
                  onToggleFavourite: () => _toggleFavourite(p),
                  expandedInci: _expandedInci,
                  onToggleInci: () =>
                      setState(() => _expandedInci = !_expandedInci),
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
    required this.favourite,
    required this.onToggleFavourite,
    required this.expandedInci,
    required this.onToggleInci,
    this.onBuy,
  });

  final Product product;
  final VoidCallback onBack;
  final VoidCallback? onAdd;
  final bool addingToShelf;
  final bool onShelf;
  final bool favourite;
  final VoidCallback onToggleFavourite;
  final bool expandedInci;
  final VoidCallback onToggleInci;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 120),
          children: [
            _Header(
              onBack: onBack,
              favourite: favourite,
              onToggleFavourite: onToggleFavourite,
            ),
            const SizedBox(height: AppSpacing.md),
            _PhotoBlock(product: product),
            const SizedBox(height: AppSpacing.lg),
            EyebrowText(product.brand,
                color: AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(product.name,
                style: AppTypography.h1.copyWith(fontSize: 28, height: 1.1)),
            const SizedBox(height: 4),
            Text(product.kindLabel, style: AppTypography.caption),
            if (product.matchBlocked) ...[
              const SizedBox(height: AppSpacing.md),
              _MatchBlockedBanner(
                reasons: product.matchWarnings.isNotEmpty
                    ? product.matchWarnings
                    : const ['Это средство не подходит твоему типу кожи'],
              ),
            ] else if (product.hasReliableMatch) ...[
              const SizedBox(height: AppSpacing.md),
              _MatchHero(
                score: product.matchScore!,
                reasons: product.matchReasons,
              ),
            ],
            if (!product.matchBlocked &&
                (product.matchReasons.isNotEmpty ||
                    product.matchWarnings.isNotEmpty)) ...[
              const SizedBox(height: AppSpacing.lg),
              EyebrowText('Почему подходит'),
              const SizedBox(height: 10),
              for (final r in product.matchReasons) ...[
                _FitRow(text: r, warn: false),
                const SizedBox(height: 8),
              ],
              for (final w in product.matchWarnings) ...[
                _FitRow(text: w, warn: true),
                const SizedBox(height: 8),
              ],
              if (product.isActive && product.matchWarnings.isEmpty)
                _FitRow(
                  text:
                      'Активный ингредиент — Лина учтёт сочетания и SPF.',
                  warn: true,
                ),
            ],
            if (product.ingredients.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              EyebrowText('Состав · INCI'),
              const SizedBox(height: 10),
              _InciCard(
                ingredients: product.ingredients,
                expanded: expandedInci,
                onToggle: onToggleInci,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            EyebrowText('Когда наносить'),
            const SizedBox(height: 10),
            _UsageRow(phase: product.routinePhase),
            if (product.description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              EyebrowText('О продукте'),
              const SizedBox(height: 8),
              Text(product.description, style: AppTypography.body),
            ],
            if (product.composition != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _LongFormSection(
                title: 'О составе',
                body: product.composition!,
              ),
            ],
            if (product.usage != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _LongFormSection(
                title: 'Как пользоваться',
                body: product.usage!,
              ),
            ],
            if (product.precautions != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _LongFormSection(
                title: 'Меры предосторожности',
                body: product.precautions!,
                emphasis: true,
              ),
            ],
            if (product.extraInfo != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _LongFormSection(
                title: 'Дополнительно',
                body: product.extraInfo!,
              ),
            ],
            if (product.adMarkerVisible &&
                product.adMarkerText != null &&
                product.adMarkerText!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxl),
              Center(
                child: Text(
                  product.adMarkerText!,
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary.withOpacity(0.5),
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _StickyBar(
            price: product.priceRub,
            onShelf: onShelf,
            onAdd: onAdd,
            adding: addingToShelf,
            onBuy: onBuy,
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.favourite,
    required this.onToggleFavourite,
  });

  final VoidCallback onBack;
  final bool favourite;
  final VoidCallback onToggleFavourite;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundButton(icon: Icons.arrow_back_ios_new, onTap: onBack),
        const Spacer(),
        _RoundButton(
          icon: favourite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: favourite ? AppColors.roseDeep : AppColors.textPrimary,
          onTap: onToggleFavourite,
        ),
        // Bookmark button removed — it duplicated the heart-favourite affordance
        // and had no real handler. One save mechanism is enough.
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.white.withOpacity(0.7),
        shape: const CircleBorder(
            side: BorderSide(color: AppColors.divider)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon,
              size: 18, color: color ?? AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _PhotoBlock extends ConsumerStatefulWidget {
  const _PhotoBlock({required this.product});
  final Product product;

  @override
  ConsumerState<_PhotoBlock> createState() => _PhotoBlockState();
}

class _PhotoBlockState extends ConsumerState<_PhotoBlock> {
  late final PageController _ctrl = PageController();
  int _index = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(backendApiProvider);
    final slots = widget.product.photoSlots;
    final hasPhotos = slots.isNotEmpty;
    final dotCount = hasPhotos ? slots.length : 1;
    return Container(
      height: 280,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Colors.white],
          stops: [0, 0.7],
        ),
        border:
            Border.all(color: AppColors.primaryAccent.withOpacity(0.18)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -50,
            child: IgnorePointer(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryAccent.withOpacity(0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!hasPhotos)
            Center(
              child: Hero(
                tag: 'bottle-${widget.product.slug}',
                child: ProductBottle(
                  product: widget.product,
                  width: 120,
                  height: 200,
                  label: widget.product.kindLabel,
                ),
              ),
            )
          else
            PageView.builder(
              controller: _ctrl,
              itemCount: slots.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: i == 0
                      ? Hero(
                          tag: 'bottle-${widget.product.slug}',
                          child: _NetworkPhoto(
                            url: api.productPhotoUrl(
                                widget.product.id,
                                slot: slots[i]),
                          ),
                        )
                      : _NetworkPhoto(
                          url: api.productPhotoUrl(widget.product.id,
                              slot: slots[i]),
                        ),
                ),
              ),
            ),
          if (dotCount > 1)
            Positioned(
              left: 16,
              bottom: 16,
              child: Row(
                children: List.generate(dotCount, (i) {
                  final on = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 6),
                    width: on ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: on
                          ? AppColors.roseDeep
                          : AppColors.textPrimary.withOpacity(0.2),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _NetworkPhoto extends StatelessWidget {
  const _NetworkPhoto({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

class _MatchHero extends StatelessWidget {
  const _MatchHero({required this.score, required this.reasons});
  final int score;
  final List<String> reasons;

  String _quote() {
    if (reasons.isNotEmpty) return reasons.first;
    if (score >= 85) return 'Точно про твою кожу — отличное попадание.';
    if (score >= 70) return 'Хорошо ложится в твой текущий уход.';
    if (score >= 55) return 'Подходит — но есть варианты лучше.';
    return 'Можно лучше — Лина подскажет аналог.';
  }

  @override
  Widget build(BuildContext context) {
    final progress = (score / 100).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.roseDeep, AppColors.roseShadow],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: IgnorePointer(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryAccent.withOpacity(0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(76, 76),
                      painter: _RingPainter(progress: progress),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$score',
                            style: AppTypography.h2.copyWith(
                              color: Colors.white,
                              fontSize: 22,
                              height: 1,
                            )),
                        const SizedBox(height: 2),
                        Text('%',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white.withOpacity(0.6),
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w500,
                            )),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'СОВПАДЕНИЕ С ТВОЕЙ КОЖЕЙ',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 10,
                        fontFamily: 'JetBrainsMono',
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '«${_quote()}»',
                      style: AppTypography.serifItalic(
                        fontSize: 17,
                        color: Colors.white,
                      ).copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width / 2) - 3;
    final track = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(c, r, track);
    final stroke = Paint()
      ..color = AppColors.primaryAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -3.141592 / 2,
      progress * 2 * 3.141592,
      false,
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress;
}

/// Hero band shown in place of the match score when the product is a hard
/// knockout for the user (wrong skin type, etc.). We don't pretend a number
/// — the message is the message.
class _MatchBlockedBanner extends StatelessWidget {
  const _MatchBlockedBanner({required this.reasons});
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.roseDeep.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.roseDeep.withOpacity(0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block_rounded,
              size: 24, color: AppColors.roseDeep),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Не для тебя',
                  style: AppTypography.h2.copyWith(
                    fontSize: 16,
                    color: AppColors.roseDeep,
                  ),
                ),
                const SizedBox(height: 4),
                for (final r in reasons)
                  Text(
                    r,
                    style: AppTypography.bodySm.copyWith(
                      fontSize: 13,
                      color: AppColors.roseDeep,
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

class _FitRow extends StatelessWidget {
  const _FitRow({required this.text, required this.warn});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final accent = warn ? AppColors.roseDeep : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withOpacity(warn ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(warn ? 0.25 : 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent,
            ),
            child: Icon(
              warn
                  ? Icons.priority_high_rounded
                  : Icons.check_rounded,
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySm.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the long-form sections (composition / usage / precautions /
/// extra). Plain card; the precautions variant uses the warning palette
/// so users actually notice contraindications.
class _LongFormSection extends StatelessWidget {
  const _LongFormSection({
    required this.title,
    required this.body,
    this.emphasis = false,
  });
  final String title;
  final String body;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final bg = emphasis ? AppColors.warning.withOpacity(0.08) : AppColors.surface;
    final border = emphasis
        ? AppColors.warning.withOpacity(0.3)
        : AppColors.divider;
    final eyebrow = emphasis ? AppColors.warning : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EyebrowText(title, color: eyebrow),
          const SizedBox(height: 8),
          Text(body, style: AppTypography.body.copyWith(height: 1.5)),
        ],
      ),
    );
  }
}

class _InciCard extends StatelessWidget {
  const _InciCard({
    required this.ingredients,
    required this.expanded,
    required this.onToggle,
  });
  final List<String> ingredients;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final preview = ingredients.take(3).toList();
    final tail = ingredients.skip(3).toList();
    final hasTail = tail.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: AppTypography.bodySm.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.55),
              children: [
                TextSpan(
                  text: preview.join(', '),
                  style: AppTypography.bodySm.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                      height: 1.55),
                ),
                if (hasTail)
                  TextSpan(text: expanded ? ', ' : ', '),
                if (hasTail)
                  TextSpan(text: expanded ? tail.join(', ') : '…'),
              ],
            ),
          ),
          if (hasTail) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onToggle,
              child: Text(
                expanded ? 'Свернуть' : 'Развернуть полностью →',
                style: AppTypography.bodySm.copyWith(
                  fontSize: 12,
                  color: AppColors.roseDeep,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.phase});
  final String phase;

  @override
  Widget build(BuildContext context) {
    final morningActive = phase == 'morning' || phase != 'evening';
    final eveningActive = phase == 'evening' || phase != 'morning';
    return Row(
      children: [
        Expanded(
          child: _UsageCard(
            icon: Icons.wb_sunny_rounded,
            label: 'Утро',
            active: morningActive,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _UsageCard(
            icon: Icons.nightlight_round,
            label: 'Вечер',
            active: eveningActive,
          ),
        ),
      ],
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.icon,
    required this.label,
    required this.active,
  });
  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: active
            ? AppColors.primaryAccent.withOpacity(0.10)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              active ? AppColors.primaryAccent : AppColors.divider,
          width: active ? 1.2 : 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 18,
              color: active
                  ? AppColors.roseDeep
                  : AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              fontSize: 14,
              color: active
                  ? AppColors.roseDeep
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyBar extends StatelessWidget {
  const _StickyBar({
    required this.price,
    required this.onShelf,
    required this.onAdd,
    required this.adding,
    this.onBuy,
  });

  final int price;
  final bool onShelf;
  final VoidCallback? onAdd;
  final bool adding;

  /// External-store CTA. When null we hide the "Купить" button entirely —
  /// products without a buy URL just keep the shelf flow.
  final VoidCallback? onBuy;

  String _formatPrice(int p) {
    final s = p.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final remain = s.length - i - 1;
      if (remain > 0 && remain % 3 == 0) buf.write(' ');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.94),
        border: Border(
          top: BorderSide(color: AppColors.divider),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Цена',
                  style: AppTypography.caption.copyWith(fontSize: 11)),
              Text(
                '${_formatPrice(price)} ₽',
                style: AppTypography.h2.copyWith(fontSize: 22),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          // When a buy URL exists, Купить is the primary action and "На полку"
          // shrinks to a circular icon button to keep both reachable.
          if (onBuy != null) ...[
            _ShelfIconButton(
              onAdd: onAdd,
              onShelf: onShelf,
              adding: adding,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Material(
                color: AppColors.roseDeep,
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: onBuy,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Купить',
                            style: AppTypography.button
                                .copyWith(color: Colors.white)),
                        const SizedBox(width: 8),
                        const Icon(Icons.north_east_rounded,
                            size: 18, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ] else
            Expanded(
              child: Material(
                color: onShelf
                    ? AppColors.primary
                    : (onAdd == null
                        ? AppColors.roseDeep.withOpacity(0.6)
                        : AppColors.roseDeep),
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: onAdd,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    child: adding
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.4,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                onShelf
                                    ? Icons.check_rounded
                                    : Icons.add_rounded,
                                size: 18,
                                color: onShelf
                                    ? AppColors.roseDeep
                                    : Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                onShelf ? 'На полке' : 'На полку',
                                style: AppTypography.button.copyWith(
                                  color: onShelf
                                      ? AppColors.roseDeep
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShelfIconButton extends StatelessWidget {
  const _ShelfIconButton({
    required this.onAdd,
    required this.onShelf,
    required this.adding,
  });
  final VoidCallback? onAdd;
  final bool onShelf;
  final bool adding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Material(
        color: onShelf ? AppColors.primary : Colors.white,
        shape: CircleBorder(
          side: BorderSide(
            color: onShelf ? AppColors.roseDeep : AppColors.divider,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onAdd,
          child: adding
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : Icon(
                  onShelf ? Icons.check_rounded : Icons.add_rounded,
                  color: AppColors.roseDeep,
                  size: 22,
                ),
        ),
      ),
    );
  }
}
