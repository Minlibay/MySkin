import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';

/// Pulls the legal document for [docKey] from the backend and renders it as
/// scrollable text. Supports a minimal subset of Markdown — `# Heading`
/// lines become h2 with serif styling, everything else is a paragraph.
/// No external markdown package: rendering needs are too small to justify it.
class LegalViewerScreen extends ConsumerStatefulWidget {
  const LegalViewerScreen({
    super.key,
    required this.docKey,
    required this.title,
    required this.onBack,
  });

  final String docKey;
  final String title;
  final VoidCallback onBack;

  @override
  ConsumerState<LegalViewerScreen> createState() => _LegalViewerScreenState();
}

class _LegalViewerScreenState extends ConsumerState<LegalViewerScreen> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(backendApiProvider).getLegal(widget.docKey);
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
                _Header(title: widget.title, onBack: widget.onBack),
                Expanded(
                  child: FutureBuilder<String>(
                    future: _future,
                    builder: (ctx, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final md = (snap.data ?? '').trim();
                      if (md.isEmpty) {
                        return _Centered(
                          icon: Icons.description_outlined,
                          title: 'Документ пока не заполнен',
                          body:
                              'Администратор приложения скоро добавит текст.',
                        );
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.sm,
                          AppSpacing.lg,
                          AppSpacing.xl,
                        ),
                        child: _MarkdownView(md),
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
  const _Header({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: AppColors.textPrimary,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(child: Text(title, style: AppTypography.h1)),
        ],
      ),
    );
  }
}

class _MarkdownView extends StatelessWidget {
  const _MarkdownView(this.markdown);
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final lines = markdown.split('\n');
    final blocks = <Widget>[];
    final buffer = <String>[];

    void flushParagraph() {
      if (buffer.isEmpty) return;
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Text(buffer.join('\n'), style: AppTypography.body),
      ));
      buffer.clear();
    }

    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('# ')) {
        flushParagraph();
        blocks.add(Padding(
          padding: const EdgeInsets.only(
              top: AppSpacing.md, bottom: AppSpacing.xs),
          child: Text(line.substring(2), style: AppTypography.h2),
        ));
      } else if (line.startsWith('## ')) {
        flushParagraph();
        blocks.add(Padding(
          padding: const EdgeInsets.only(
              top: AppSpacing.sm, bottom: AppSpacing.xxs),
          child: Text(line.substring(3), style: AppTypography.h3),
        ));
      } else if (line.isEmpty) {
        flushParagraph();
      } else {
        buffer.add(line);
      }
    }
    flushParagraph();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: AppTypography.h2, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(body,
                style: AppTypography.bodySecondary,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
