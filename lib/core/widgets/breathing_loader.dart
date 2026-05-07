import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class BreathingLoader extends StatefulWidget {
  const BreathingLoader({super.key, this.size = 96});
  final double size;

  @override
  State<BreathingLoader> createState() => _BreathingLoaderState();
}

class _BreathingLoaderState extends State<BreathingLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size * (0.7 + 0.3 * t),
                height: widget.size * (0.7 + 0.3 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.6 - 0.4 * t),
                ),
              ),
              Container(
                width: widget.size * 0.55,
                height: widget.size * 0.55,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryAccent,
                ),
                child: const Icon(Icons.spa,
                    color: Colors.white, size: 28),
              ),
            ],
          ),
        );
      },
    );
  }
}
