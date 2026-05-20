import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';
import '../domain/pro_status.dart';

/// Pro subscription upsell screen. Stateful only so it can show the
/// active-subscription banner when the user is already on Pro (manual
/// grants from admin / future promo redemptions). The "Перейти на Pro"
/// button currently opens a "Coming soon" sheet — real payment lands
/// in the next iteration (StoreKit on iOS, ЮKassa on RuStore).
class ProUpgradeScreen extends ConsumerStatefulWidget {
  const ProUpgradeScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<ProUpgradeScreen> createState() => _ProUpgradeScreenState();
}

class _ProUpgradeScreenState extends ConsumerState<ProUpgradeScreen> {
  ProStatus _status = ProStatus.free;
  bool _loadingStatus = true;

  static const _benefits = <_Benefit>[
    _Benefit(
      icon: Icons.local_offer_outlined,
      title: 'Эксклюзивные промокоды',
      sub: 'Скидки от партнёров на средства из каталога — только для Pro.',
    ),
    _Benefit(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'Безлимит диалогов с Линой',
      sub: 'Сколько угодно вопросов, без дневного ограничения.',
    ),
    _Benefit(
      icon: Icons.auto_awesome_outlined,
      title: 'Приоритетный анализ фото',
      sub: 'Карта улучшений считается первой, без очереди.',
    ),
    _Benefit(
      icon: Icons.history_rounded,
      title: 'Расширенная история',
      sub: 'Все сканы за всё время — а не только последний месяц.',
    ),
    _Benefit(
      icon: Icons.rocket_launch_outlined,
      title: 'Ранний доступ к новинкам',
      sub: 'Новые функции — у тебя раньше, чем у всех.',
    ),
    _Benefit(
      icon: Icons.workspace_premium_outlined,
      title: 'Бейдж Pro в профиле',
      sub: 'Видно тебе и в чате с Линой.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStatus());
  }

  Future<void> _loadStatus() async {
    try {
      final s = await ref.read(backendApiProvider).getProStatus();
      if (!mounted) return;
      setState(() {
        _status = s;
        _loadingStatus = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStatus = false);
    }
  }

  void _onUpgradeTap() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _ComingSoonSheet(),
    );
  }

  String _formatUntil(DateTime d) {
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: GlowBackground(variant: GlowVariant.blush),
          ),
          SafeArea(
            child: Column(
              children: [
                _Header(onBack: widget.onBack),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                    children: [
                      _HeroCard(
                        status: _status,
                        loading: _loadingStatus,
                        formatUntil: _formatUntil,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const EyebrowText('Что входит в Pro'),
                      const SizedBox(height: AppSpacing.sm),
                      for (final b in _benefits) ...[
                        _BenefitTile(item: b),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Подписку можно отменить в любой момент. После '
                        'отмены доступ к Pro сохраняется до конца '
                        'оплаченного периода.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _BottomBar(
                  status: _status,
                  onUpgrade: _onUpgradeTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefit {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.sub,
  });
  final IconData icon;
  final String title;
  final String sub;
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
          Text(
            'Pro',
            style: AppTypography.h1.copyWith(fontSize: 24),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.status,
    required this.loading,
    required this.formatUntil,
  });

  final ProStatus status;
  final bool loading;
  final String Function(DateTime) formatUntil;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.roseDeep, AppColors.roseShadow],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  status.isPro ? 'PRO АКТИВЕН' : 'МОЯ КОЖА · PRO',
                  style: AppTypography.eyebrow(
                    color: Colors.white,
                  ).copyWith(letterSpacing: 1.5),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: status.isPro
                      ? 'Спасибо за\n'
                      : 'Больше от\n',
                  style: AppTypography.h1.copyWith(
                    fontSize: 32,
                    color: Colors.white,
                    height: 1.1,
                  )),
              TextSpan(
                text: status.isPro ? 'поддержки' : 'Лины каждый день',
                style: AppTypography.serifItalic(
                  fontSize: 32,
                  color: Colors.white,
                ).copyWith(height: 1.1),
              ),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
          if (status.isPro && status.proUntil != null)
            Text(
              'Подписка активна до ${formatUntil(status.proUntil!)}',
              style: AppTypography.body.copyWith(
                color: Colors.white.withOpacity(0.85),
                height: 1.4,
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '199 ₽',
                  style: AppTypography.display.copyWith(
                    fontSize: 44,
                    height: 1,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '/ месяц',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          if (loading) ...[
            const SizedBox(height: 12),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.item});
  final _Benefit item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.blush,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon,
                color: AppColors.roseDeep, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 4),
                Text(item.sub,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.status, required this.onUpgrade});

  final ProStatus status;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    if (status.isPro) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline_rounded,
                  color: AppColors.success, size: 18),
              const SizedBox(width: 8),
              Text(
                'Pro уже активен',
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: onUpgrade,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.roseDeep,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Перейти на Pro', style: AppTypography.button),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingSoonSheet extends StatelessWidget {
  const _ComingSoonSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 12, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.dividerStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.blush,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.workspace_premium_rounded,
                color: AppColors.roseDeep, size: 36),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Pro скоро откроется',
            style: AppTypography.h1.copyWith(fontSize: 24),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Сейчас мы настраиваем оплату через App Store и RuStore. '
            'Как только всё будет готово — ты сможешь оформить Pro '
            'прямо отсюда. Мы напомним.',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.roseDeep,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const StadiumBorder(),
              ),
              child: Text('Хорошо', style: AppTypography.button),
            ),
          ),
        ],
      ),
    );
  }
}
