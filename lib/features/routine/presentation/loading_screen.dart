import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/breathing_loader.dart';

class AILoadingScreen extends StatefulWidget {
  const AILoadingScreen({super.key, this.messages, this.onCancel});

  final List<String>? messages;
  final VoidCallback? onCancel;

  @override
  State<AILoadingScreen> createState() => _AILoadingScreenState();
}

class _AILoadingScreenState extends State<AILoadingScreen> {
  static const _defaultMessages = [
    'Анализируем кожу...',
    'Подбираем уход...',
    'Создаём персональную формулу...',
  ];

  late final List<String> _messages = widget.messages ?? _defaultMessages;
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const BreathingLoader(size: 120),
                    const SizedBox(height: AppSpacing.xl),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        _messages[_index],
                        key: ValueKey(_index),
                        style: AppTypography.h2,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onCancel != null)
                Positioned(
                  bottom: 0,
                  child: TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Отмена'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
