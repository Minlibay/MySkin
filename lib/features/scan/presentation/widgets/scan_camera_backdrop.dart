import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full-screen camera preview that scales to cover and centers horizontally.
/// Shows a warm dark gradient when [errorText] is non-null (no permission /
/// no camera available) and a flat dark fill while the controller initialises.
class ScanCameraBackdrop extends StatelessWidget {
  const ScanCameraBackdrop({
    super.key,
    required this.controller,
    required this.initFuture,
    required this.errorText,
  });

  final CameraController? controller;
  final Future<void>? initFuture;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    if (errorText != null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.1,
            colors: [
              Color(0xFF5A3744),
              Color(0xFF2A1A20),
              Color(0xFF0F0A0C),
            ],
            stops: [0, 0.45, 1],
          ),
        ),
      );
    }
    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snap) {
        final c = controller;
        if (c == null || !c.value.isInitialized) {
          return Container(color: const Color(0xFF1A1116));
        }
        final size = MediaQuery.of(context).size;
        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.width,
                height: size.width * c.value.aspectRatio,
                child: CameraPreview(c),
              ),
            ),
          ),
        );
      },
    );
  }
}
