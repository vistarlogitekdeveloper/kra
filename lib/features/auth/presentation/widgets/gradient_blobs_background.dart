import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// Decorative gradient blobs in the background.
/// Pure CSS-of-Flutter — no images, no animations heavy enough to drop frames.
class GradientBlobsBackground extends StatelessWidget {
  const GradientBlobsBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base gradient
        Container(
          decoration: const BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
        ),
        // Top-right purple blob
        Positioned(
          top: -120,
          right: -80,
          child: _Blob(
            size: 320,
            color: AppColors.primaryPurple.withValues(alpha: 0.18),
          ),
        ),
        // Bottom-left orange blob
        Positioned(
          bottom: -140,
          left: -100,
          child: _Blob(
            size: 360,
            color: AppColors.accentOrange.withValues(alpha: 0.14),
          ),
        ),
        // Mid-right yellow accent
        Positioned(
          top: 280,
          right: -60,
          child: _Blob(
            size: 180,
            color: AppColors.accentYellow.withValues(alpha: 0.16),
          ),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 80,
            spreadRadius: 40,
          ),
        ],
      ),
    );
  }
}
