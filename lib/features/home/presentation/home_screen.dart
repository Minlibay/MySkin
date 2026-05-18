import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/floating_tab_bar.dart';
import '../../../core/widgets/glow_background.dart';
import '../../../core/widgets/lina_avatar.dart';
import '../../../core/widgets/metric_ring.dart';
import '../../ai/domain/models.dart';
import '../../../core/telemetry/product_telemetry.dart';
import '../../api/backend_api.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/product_bottle.dart';
import '../../notifications/data/notifications_controller.dart';
import '../../ritual/domain/today.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.profile,
    required this.lastResult,
    this.today,
    required this.onStandardMode,
    required this.onDermMode,
    required this.onRetake,
    this.onLogout,
    this.onOpenRoutine,
    this.onOpenCatalog,
    this.onOpenShelf,
    this.onOpenScan,
    this.onOpenProduct,
    this.onOpenNotifications,
  });

  final SkinProfile profile;
  final RoutineResult? lastResult;
  final Today? today;
  final VoidCallback onStandardMode;
  final VoidCallback onDermMode;
  final VoidCallback onRetake;
  final VoidCallback? onLogout;
  final VoidCallback? onOpenRoutine;
  final VoidCallback? onOpenCatalog;
  final VoidCallback? onOpenShelf;
  final VoidCallback? onOpenScan;
  final ValueChanged<Product>? onOpenProduct;
  final VoidCallback? onOpenNotifications;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<Product>> _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = _loadTopMatches();
    // Refresh unread badge on the bell each time home becomes visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsControllerProvider.notifier).refreshUnreadCount();
    });
  }

  Future<List<Product>> _loadTopMatches() async {
    final items = await ref.read(backendApiProvider).listCatalog();
    final scored = items.where((p) => p.hasReliableMatch).toList()
      ..sort((a, b) => (b.matchScore ?? 0).compareTo(a.matchScore ?? 0));
    return scored.take(8).toList();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'Доброй ночи';
    if (h < 12) return 'Доброе утро';
    if (h < 18) return 'Добрый день';
    return 'Добрый вечер';
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final lastResult = widget.lastResult;
    final today = widget.today;
    final name = profile.name?.trim().isNotEmpty == true ? profile.name! : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: GlowBackground(variant: GlowVariant.blush),
          ),
          SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 110),
                  children: [
                    _Greeting(
                      greeting: _greeting,
                      name: name,
                      onLogout: widget.onLogout,
                      onRetake: widget.onRetake,
                      onOpenNotifications: widget.onOpenNotifications,
                      notificationsUnread: ref.watch(
                        notificationsControllerProvider
                            .select((s) => s.unreadCount),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (lastResult != null) ...[
                      // ───────── СЕГОДНЯ ─────────
                      // Zone label intentionally absent here — the TodayHero
                      // card already carries 'Сегодня · <дата>' as its own
                      // eyebrow, and printing 'Сегодня' twice in a row felt
                      // redundant on a tight scroll.
                      _TodayHeroCard(result: lastResult),
                      const SizedBox(height: AppSpacing.sm + 2),
                      _LinaNudge(
                        message: lastResult.tips.isNotEmpty
                            ? '«${lastResult.tips.first}»'
                            : '«Заметила, что вечерний уход важен — давай не пропускать.»',
                        onTap: widget.onDermMode,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionRow(
                        title: 'Ритуал',
                        actionLabel: 'Открыть',
                        onTap: widget.onOpenRoutine,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _RitualRow(
                        result: lastResult,
                        today: today,
                        onTap: widget.onOpenRoutine,
                      ),
                      const SizedBox(height: AppSpacing.sm + 2),
                      _StreakCard(streak: today?.streak ?? 0),
                      const SizedBox(height: AppSpacing.xxl),
                      const _ZoneDivider(),
                      const SizedBox(height: AppSpacing.lg),
                      // ───────── ПОДОБРАТЬ И УЗНАТЬ ─────────
                      const EyebrowText(
                        'Подобрать и узнать',
                        color: AppColors.roseDeep,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _SectionRow(
                        title: 'Подобрано тебе',
                        actionLabel: 'Каталог',
                        onTap: widget.onOpenCatalog,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _MatchedProductsStrip(
                        future: _catalog,
                        onOpen: widget.onOpenProduct,
                        onOpenCatalog: widget.onOpenCatalog,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionRow(title: 'Обновить уход'),
                      const SizedBox(height: AppSpacing.sm),
                    ] else ...[
                      _EmptyHero(isMale: profile.isMale),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionRow(title: 'Подобрать уход'),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    if (widget.onOpenScan != null) ...[
                      _ModeCard(
                        icon: Icons.center_focus_strong_rounded,
                        title: 'Сканировать кожу',
                        subtitle:
                            'Селфи и точные метрики — самый честный совет.',
                        onTap: widget.onOpenScan!,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    _ModeCard(
                      icon: Icons.bolt_rounded,
                      title: 'Быстрая рекомендация',
                      subtitle:
                          'Пара вопросов о коже сегодня — готовый уход за минуту.',
                      onTap: widget.onStandardMode,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ModeCard(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Лина · диалог',
                      subtitle:
                          'Углублённый разбор с уточняющими вопросами.',
                      tinted: true,
                      onTap: widget.onDermMode,
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FloatingTabBar(
                    active: AppTab.home,
                    onSelect: (t) {
                      switch (t) {
                        case AppTab.routine:
                          widget.onOpenRoutine?.call();
                        case AppTab.chat:
                          widget.onDermMode();
                        case AppTab.catalog:
                          widget.onOpenCatalog?.call();
                        case AppTab.profile:
                          widget.onOpenShelf?.call();
                        case AppTab.home:
                          break;
                      }
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

class _MatchedProductsStrip extends ConsumerWidget {
  const _MatchedProductsStrip({
    required this.future,
    required this.onOpen,
    required this.onOpenCatalog,
  });

  final Future<List<Product>> future;
  final ValueChanged<Product>? onOpen;
  final VoidCallback? onOpenCatalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 210,
      child: FutureBuilder<List<Product>>(
        future: future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: AppColors.primaryAccent,
                  strokeWidth: 2,
                ),
              ),
            );
          }
          final items = snap.data ?? const <Product>[];
          if (items.isEmpty) {
            return _EmptyStrip(onOpenCatalog: onOpenCatalog);
          }
          // Fire impressions for everything in the strip on first paint —
          // ProductTelemetry dedups per session, so re-renders are free.
          final telemetry = ref.read(productTelemetryProvider);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (final p in items) {
              telemetry.impression(p.id, ProductSurface.recommendation);
            }
          });
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            padding: EdgeInsets.zero,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _MatchedProductCard(
              product: items[i],
              onTap: () {
                telemetry.open(items[i].id, ProductSurface.recommendation);
                onOpen?.call(items[i]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _MatchedProductCard extends StatelessWidget {
  const _MatchedProductCard({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reason = product.matchReasons.isNotEmpty
        ? product.matchReasons.first
        : product.kindLabel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 156,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.hasReliableMatch)
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
                        '${product.matchScore}%',
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.roseDeep,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Center(
                child: ProductBottle(
                  product: product,
                  width: 50,
                  height: 76,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                product.brand,
                style: AppTypography.eyebrow().copyWith(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                product.name,
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                reason,
                style: AppTypography.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyStrip extends StatelessWidget {
  const _EmptyStrip({required this.onOpenCatalog});
  final VoidCallback? onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpenCatalog,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 18, vertical: 22),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.roseDeep, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Открой каталог — Лина подберёт средства под твою кожу',
                  style: AppTypography.bodySecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.greeting,
    required this.name,
    this.onLogout,
    this.onRetake,
    this.onOpenNotifications,
    this.notificationsUnread = 0,
  });
  final String greeting;
  final String? name;
  final VoidCallback? onLogout;
  final VoidCallback? onRetake;
  final VoidCallback? onOpenNotifications;
  final int notificationsUnread;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.blush2],
            ),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryAccent.withOpacity(0.5),
                blurRadius: 14,
                offset: const Offset(0, 4),
                spreadRadius: -4,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            (name?.isNotEmpty ?? false) ? name![0].toUpperCase() : 'Я',
            style: AppTypography.serifItalic(
              fontSize: 18,
              color: AppColors.roseDeep,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting,
                  style: AppTypography.caption.copyWith(fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                name ?? 'Привет',
                style: AppTypography.h2,
              ),
            ],
          ),
        ),
        _CircleIconButton(
          icon: Icons.notifications_none_rounded,
          dot: notificationsUnread > 0,
          onTap: onOpenNotifications ?? () {},
        ),
        const SizedBox(width: AppSpacing.xs),
        _CircleIconButton(
          icon: Icons.more_horiz_rounded,
          onTap: () => _showMenu(context),
        ),
      ],
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.dividerStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.refresh_rounded,
                  color: AppColors.textPrimary),
              title: Text('Пройти заново', style: AppTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                onRetake?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded,
                  color: AppColors.textPrimary),
              title: Text('Выйти', style: AppTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                onLogout?.call();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.dot = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white.withOpacity(0.7),
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.divider),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(icon, size: 20, color: AppColors.textPrimary),
            ),
          ),
          if (dot)
            Positioned(
              top: 10,
              right: 12,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.roseDeep,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayHeroCard extends StatelessWidget {
  const _TodayHeroCard({required this.result});
  final RoutineResult result;

  @override
  Widget build(BuildContext context) {
    final score = result.skinScore ?? 70;
    final summary = result.skinSummary;
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border:
                Border.all(color: AppColors.primaryAccent.withOpacity(0.18)),
            gradient: const LinearGradient(
              begin: Alignment(-0.6, -1),
              end: Alignment(1, 1),
              colors: [Colors.white, AppColors.primary],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryAccent.withOpacity(0.3),
                blurRadius: 40,
                offset: const Offset(0, 18),
                spreadRadius: -16,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EyebrowText(_dateLabel(), color: AppColors.roseDeep),
              const SizedBox(height: AppSpacing.md),
              // Hero row: large score ring as visual anchor + a short mood
              // label. The big number inside the ring already says "78",
              // so this column is intentionally compact text only.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  MetricRing(
                    value: score,
                    size: 84,
                    stroke: 6,
                    color: AppColors.roseDeep,
                    suffix: null,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Индекс кожи',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _moodLabel(score),
                          style: AppTypography.h2.copyWith(
                            fontSize: 22,
                            color: AppColors.roseDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // Quiet hairline.
              Container(height: 1, color: AppColors.divider),
              const SizedBox(height: AppSpacing.md),
              const _MetricBar(
                label: 'Увлажнение',
                value: 78,
                color: AppColors.info,
              ),
              const SizedBox(height: 10),
              const _MetricBar(
                label: 'Тон',
                value: 67,
                color: AppColors.primaryAccent,
              ),
              if (summary != null && summary.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  '«${summary.trim()}»',
                  style: AppTypography.serifItalic(
                    fontSize: 15,
                    color: AppColors.roseDeep,
                  ).copyWith(height: 1.4),
                ),
              ],
            ],
          ),
        ),
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
                    AppColors.primaryAccent.withOpacity(0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _moodLabel(int score) {
    if (score >= 85) return 'Сияет';
    if (score >= 70) return 'Хорошо';
    if (score >= 55) return 'Стабильно';
    if (score >= 40) return 'Нужна поддержка';
    return 'Просит внимания';
  }

  String _dateLabel() {
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    final d = DateTime.now();
    return 'Сегодня · ${d.day} ${months[d.month]}';
  }
}

class _MetricBar extends StatelessWidget {
  const _MetricBar({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: AppTypography.micro.copyWith(fontSize: 11)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              tween: Tween(begin: 0, end: value / 100),
              builder: (_, t, __) => LinearProgressIndicator(
                value: t,
                minHeight: 4,
                backgroundColor:
                    AppColors.primaryAccent.withOpacity(0.18),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: AppTypography.eyebrow().copyWith(
              fontSize: 11,
              color: AppColors.textPrimary,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _LinaNudge extends StatelessWidget {
  const _LinaNudge({required this.message, this.onTap});

  /// Raw message — quotes are added by this widget, callers should NOT wrap
  /// the text in « » themselves.
  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Strip wrapping quotes if a caller already added them (legacy behaviour
    // — old code passed pre-quoted strings). Keeps render consistent.
    var msg = message.trim();
    if (msg.startsWith('«') && msg.endsWith('»')) {
      msg = msg.substring(1, msg.length - 1).trim();
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.surface, AppColors.blush],
            ),
            border:
                Border.all(color: AppColors.primaryAccent.withOpacity(0.22)),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative sparkle in the corner — purely visual flourish.
              Positioned(
                right: 14,
                top: 14,
                child: Text(
                  '✦',
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.primaryAccent.withOpacity(0.45),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const LinaAvatar(size: 44, monogram: true),
                        const SizedBox(width: 12),
                        // Single online signal — the green dot on the avatar
                        // itself. The 'на связи' pill underneath duplicated
                        // it; one indicator reads cleaner.
                        Text(
                          'ЛИНА · СОВЕТ',
                          style: AppTypography.eyebrow(
                            color: AppColors.roseDeep,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '«$msg»',
                      style: AppTypography.serifItalic(
                        fontSize: 18,
                        color: AppColors.roseDeep,
                      ).copyWith(height: 1.35),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Спросить о коже',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.roseDeep,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: AppColors.roseDeep,
                        ),
                      ],
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

/// Quiet horizontal rule used to break the home feed into two visual zones —
/// what matters today vs. what to explore next. Fades to transparent at the
/// edges so it never looks like a hard structural seam.
class _ZoneDivider extends StatelessWidget {
  const _ZoneDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.dividerStrong.withOpacity(0),
              AppColors.dividerStrong,
              AppColors.dividerStrong.withOpacity(0),
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.title,
    this.actionLabel,
    this.onTap,
  });
  final String title;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(title, style: AppTypography.h2)),
        if (actionLabel != null && onTap != null)
          GestureDetector(
            onTap: onTap,
            child: Text(
              '$actionLabel →',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.roseDeep,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class _RitualRow extends StatelessWidget {
  const _RitualRow({required this.result, this.today, this.onTap});
  final RoutineResult result;
  final Today? today;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RitualCard(
            icon: Icons.wb_sunny_rounded,
            label: 'Утро',
            steps: result.morning.length,
            done: today?.morningDone ?? 0,
            tinted: false,
            onTap: onTap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RitualCard(
            icon: Icons.nightlight_round,
            label: 'Вечер',
            steps: result.evening.length,
            done: today?.eveningDone ?? 0,
            tinted: true,
            onTap: onTap,
          ),
        ),
      ],
    );
  }
}

class _RitualCard extends StatelessWidget {
  const _RitualCard({
    required this.icon,
    required this.label,
    required this.steps,
    required this.done,
    required this.tinted,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final int steps;
  final int done;
  final bool tinted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.primaryAccent.withOpacity(0.15)),
            gradient: tinted
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, Colors.white],
                  )
                : null,
            color: tinted ? null : AppColors.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryAccent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: AppColors.roseDeep),
              ),
              const SizedBox(height: 10),
              Text(label, style: AppTypography.bodyMedium),
              const SizedBox(height: 2),
              Text(
                '$steps шаг${_ending(steps)} · ~${steps * 2} мин',
                style: AppTypography.caption.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 600),
                        tween: Tween(
                            begin: 0,
                            end: steps == 0 ? 0 : done / steps),
                        builder: (_, t, __) => LinearProgressIndicator(
                          value: t,
                          minHeight: 4,
                          backgroundColor:
                              AppColors.primaryAccent.withOpacity(0.18),
                          valueColor: AlwaysStoppedAnimation(
                            done == steps && steps > 0
                                ? AppColors.success
                                : AppColors.primaryAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$done/$steps',
                    style: AppTypography.eyebrow().copyWith(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ending(int n) {
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 == 1 && m100 != 11) return '';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'а';
    return 'ов';
  }
}


class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    final hasStreak = streak > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.champagne, Colors.white],
        ),
        border: Border.all(color: AppColors.gold.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasStreak
                      ? '$streak ${_dayWord(streak)} без пропусков'
                      : 'Начни серию сегодня',
                  style: AppTypography.bodySm
                      .copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  hasStreak
                      ? 'Кожа замечает постоянство — продолжай.'
                      : 'Отметь хотя бы один шаг — серия начнётся.',
                  style: AppTypography.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dayWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero({this.isMale = false});

  final bool isMale;

  @override
  Widget build(BuildContext context) {
    // "Готов(а)" — gender-aware. Default (unknown gender) reads as feminine
    // because that's the historical default; once the user picks during
    // onboarding it switches to "Готов" for men.
    final ready = isMale ? 'Готов подобрать ' : 'Готова подобрать ';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border:
            Border.all(color: AppColors.primaryAccent.withOpacity(0.18)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, AppColors.primary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EyebrowText('Начало', color: AppColors.roseDeep),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: ready, style: AppTypography.h1),
                TextSpan(
                    text: 'первый',
                    style: AppTypography.serifItalic(fontSize: 28)),
                TextSpan(text: ' уход', style: AppTypography.h1),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Анкета пройдена. Выбери режим ниже — Лина подберёт продукты под твою кожу.',
            style: AppTypography.bodySecondary.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tinted = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tinted ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: tinted
                  ? AppColors.primaryAccent.withOpacity(0.25)
                  : AppColors.divider,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tinted
                      ? Colors.white.withOpacity(0.7)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: AppColors.roseDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  size: 20, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
