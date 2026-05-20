import 'package:flutter/material.dart';

/// Wraps [child] and invokes [onBack] when the user performs a left-edge
/// horizontal drag (back gesture) toward the centre of the screen. Works on
/// both Android and iOS regardless of route type — the app's internal screens
/// are switched via setState, not Navigator, so the OS edge-back gesture
/// would not otherwise pop them.
class SwipeBack extends StatelessWidget {
  const SwipeBack({super.key, required this.onBack, required this.child});

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 22,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v > 200) onBack();
            },
          ),
        ),
      ],
    );
  }
}
