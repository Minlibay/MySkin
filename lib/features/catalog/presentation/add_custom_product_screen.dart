import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/glow_background.dart';
import '../../api/backend_api.dart';
import '../../notifications/data/local_notifications.dart';

/// Form for adding the user's own already-purchased product to the shelf.
/// Does NOT touch the public catalog — server stores it in
/// `user_custom_products` keyed by the current user.
class AddCustomProductScreen extends ConsumerStatefulWidget {
  const AddCustomProductScreen({
    super.key,
    required this.onSaved,
    required this.onBack,
  });

  final VoidCallback onSaved;
  final VoidCallback onBack;

  @override
  ConsumerState<AddCustomProductScreen> createState() =>
      _AddCustomProductScreenState();
}

class _AddCustomProductScreenState
    extends ConsumerState<AddCustomProductScreen> {
  final _brandCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _kind = 'serum';
  String? _fillLevel = 'full';
  int? _paoMonths;
  DateTime? _openedAt;
  DateTime? _expiresAt;
  Uint8List? _photoBytes;
  String _photoMime = 'image/jpeg';
  bool _saving = false;

  static const _kinds = <(String, String)>[
    ('cleanser', 'Очищение'),
    ('scrub', 'Скраб'),
    ('peeling', 'Пилинг'),
    ('toner', 'Тоник'),
    ('pad', 'Пэды'),
    ('essence', 'Эссенция'),
    ('mask', 'Маска'),
    ('eye_patch', 'Патчи для глаз'),
    ('serum', 'Сыворотка'),
    ('eye_serum', 'Сыворотка для глаз'),
    ('eye_cream', 'Крем для глаз'),
    ('moisturizer', 'Крем'),
    ('spf', 'SPF'),
  ];

  static const _paoOptions = <int>[3, 6, 9, 12, 18, 24, 36];
  static const _fillOptions = <(String, String)>[
    ('full', 'Полный'),
    ('half', 'Половина'),
    ('low', 'Заканчивается'),
    ('empty', 'Закончился'),
  ];

  @override
  void dispose() {
    _brandCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1000,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 4 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фото слишком большое (>4 МБ)')),
      );
      return;
    }
    setState(() {
      _photoBytes = bytes;
      _photoMime = picked.mimeType ?? 'image/jpeg';
    });
  }

  Future<void> _pickDate(bool opened) async {
    final now = DateTime.now();
    final initial = opened ? (_openedAt ?? now) : (_expiresAt ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (opened) {
        _openedAt = picked;
      } else {
        _expiresAt = picked;
      }
    });
  }

  Future<void> _save() async {
    final brand = _brandCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (brand.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполни бренд и название')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(backendApiProvider).addCustomProduct(
            brand: brand,
            name: name,
            kind: _kind,
            fillLevel: _fillLevel,
            openedAt: _openedAt,
            expiresAt: _expiresAt,
            paoMonths: _paoMonths,
            photoBase64:
                _photoBytes != null ? base64Encode(_photoBytes!) : null,
            photoMime: _photoMime,
          );
      // If the user provided expiry info, ask for notifications permission
      // right after the save — that's the moment with highest grant rate.
      if (_expiresAt != null ||
          (_paoMonths != null && _openedAt != null)) {
        await ref.read(localNotificationsProvider).requestPermission();
      }
      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не получилось: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
              child: GlowBackground(variant: GlowVariant.champagne)),
          SafeArea(
            child: Column(
              children: [
                _Header(onBack: widget.onBack),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                        AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
                    children: [
                      _PhotoPicker(
                        bytes: _photoBytes,
                        onPick: _pickPhoto,
                        onClear: () => setState(() => _photoBytes = null),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _label('Бренд'),
                      _field(_brandCtrl, hint: 'CeraVe, La Roche-Posay…'),
                      const SizedBox(height: AppSpacing.md),
                      _label('Название'),
                      _field(_nameCtrl, hint: 'Hydrating Cleanser'),
                      const SizedBox(height: AppSpacing.md),
                      _label('Категория'),
                      _KindGrid(
                        value: _kind,
                        onChange: (v) => setState(() => _kind = v),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _label('Уровень в банке'),
                      _FillChips(
                        value: _fillLevel,
                        onChange: (v) => setState(() => _fillLevel = v),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _label('Срок годности и открытие'),
                      _DateRow(
                        label: 'Открыто',
                        value: _openedAt,
                        onPick: () => _pickDate(true),
                        onClear: () => setState(() => _openedAt = null),
                      ),
                      const SizedBox(height: 8),
                      _DateRow(
                        label: 'Годен до',
                        value: _expiresAt,
                        onPick: () => _pickDate(false),
                        onClear: () => setState(() => _expiresAt = null),
                      ),
                      const SizedBox(height: 8),
                      _PaoSelector(
                        value: _paoMonths,
                        options: _paoOptions,
                        onChange: (v) => setState(() => _paoMonths = v),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppButton(
                        label: _saving ? 'Сохраняю…' : 'Добавить на полку',
                        onPressed: _saving ? null : _save,
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: EyebrowText(text, color: AppColors.roseDeep),
      );

  Widget _field(TextEditingController c, {String? hint}) => TextField(
        controller: c,
        style: AppTypography.body,
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.roseDeep),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
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
                const EyebrowText('Своё средство',
                    color: AppColors.roseDeep),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'Добавить ',
                        style: AppTypography.h1.copyWith(fontSize: 26)),
                    TextSpan(
                      text: 'на полку',
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

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker(
      {required this.bytes, required this.onPick, required this.onClear});
  final Uint8List? bytes;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes!, fit: BoxFit.cover)
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_a_photo_outlined,
                        size: 32, color: AppColors.textSecondary),
                    const SizedBox(height: 6),
                    Text('Фото банки',
                        style: AppTypography.bodySecondary),
                  ],
                ),
              ),
            if (bytes != null)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onClear,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KindGrid extends StatelessWidget {
  const _KindGrid({required this.value, required this.onChange});
  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final k in _AddCustomProductScreenState._kinds)
          _PillChip(
            label: k.$2,
            active: value == k.$1,
            onTap: () => onChange(k.$1),
          ),
      ],
    );
  }
}

class _FillChips extends StatelessWidget {
  const _FillChips({required this.value, required this.onChange});
  final String? value;
  final ValueChanged<String?> onChange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final f in _AddCustomProductScreenState._fillOptions)
          _PillChip(
            label: f.$2,
            active: value == f.$1,
            onTap: () => onChange(f.$1),
          ),
      ],
    );
  }
}

class _PaoSelector extends StatelessWidget {
  const _PaoSelector({
    required this.value,
    required this.options,
    required this.onChange,
  });
  final int? value;
  final List<int> options;
  final ValueChanged<int?> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'PAO',
          style: AppTypography.bodySm.copyWith(
              fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final m in options)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _PillChip(
                      label: '${m}M',
                      active: value == m,
                      onTap: () => onChange(value == m ? null : m),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onPick,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_outlined,
                        size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text('$label: ',
                        style: AppTypography.bodySecondary),
                    Text(
                      value == null
                          ? 'не указана'
                          : '${value!.day.toString().padLeft(2, '0')}.'
                              '${value!.month.toString().padLeft(2, '0')}.'
                              '${value!.year}',
                      style: AppTypography.body.copyWith(
                        color: value == null
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (value != null)
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.textSecondary,
          ),
      ],
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: active ? AppColors.roseDeep : AppColors.surface,
            border: Border.all(
              color: active ? AppColors.roseDeep : AppColors.divider,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.bodySm.copyWith(
              fontSize: 13,
              color: active ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
