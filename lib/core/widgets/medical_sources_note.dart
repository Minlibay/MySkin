import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Cited sources block shown under medical recommendations (scan results,
/// routine cards). Required by App Store Review Guideline 1.4.1 — apps
/// surfacing medical/health information must show citations to the
/// underlying sources, with easy access for the user.
class MedicalSourcesNote extends StatelessWidget {
  const MedicalSourcesNote({super.key});

  static const List<_Source> _sources = [
    _Source(
      label: 'American Academy of Dermatology',
      detail: 'клинические рекомендации по уходу за кожей и дерматологическим состояниям',
      url: 'https://www.aad.org/public/everyday-care',
    ),
    _Source(
      label: 'DermNet (New Zealand)',
      detail: 'международная база описаний кожных состояний и протоколов ухода',
      url: 'https://dermnetnz.org/topics',
    ),
    _Source(
      label: 'PubMed / NCBI',
      detail: 'рецензируемые публикации NIH по дерматологии, барьеру кожи, активным ингредиентам',
      url: 'https://pubmed.ncbi.nlm.nih.gov/?term=skin+barrier',
    ),
    _Source(
      label: 'EADV — European Academy of Dermatology and Venereology',
      detail: 'европейские гайдлайны по акне, розацеа, пигментации',
      url: 'https://www.eadv.org/patient-corner',
    ),
    _Source(
      label: 'Cochrane Skin Group',
      detail: 'систематические обзоры эффективности дерматологических вмешательств',
      url: 'https://skin.cochrane.org',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded,
                  size: 16, color: AppColors.roseDeep),
              const SizedBox(width: 8),
              Text(
                'Источники рекомендаций',
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Рекомендации формируются на основе международных дерматологических руководств:',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          for (final s in _sources) _SourceTile(source: s),
        ],
      ),
    );
  }
}

class _Source {
  const _Source({
    required this.label,
    required this.detail,
    required this.url,
  });
  final String label;
  final String detail;
  final String url;
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});
  final _Source source;

  Future<void> _open() async {
    final uri = Uri.parse(source.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(Icons.north_east_rounded,
                  size: 12, color: AppColors.roseDeep),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.label,
                    style: AppTypography.bodyMedium.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.roseDeep,
                      decoration: TextDecoration.underline,
                      decorationColor:
                          AppColors.roseDeep.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    source.detail,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
