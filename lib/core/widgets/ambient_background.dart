import 'package:flutter/material.dart';

import '../constants/app_assets.dart';
import '../constants/app_colors.dart';

/// The Vistar Premium ambient page background — three aurora radial glows
/// (purple top-left, pink top-right, orange bottom-right) sweeping across a
/// near-black canvas, with a faint rotated "S" watermark at the right edge.
///
/// Wrap any signature surface (splash, login, dashboard hero) with this
/// widget. The watermark falls back to a transparent box if the dedicated
/// `vistar_s_mark.png` hasn't been dropped into `assets/images/` yet, so
/// using this widget never breaks the build.
///
/// ```dart
/// Scaffold(
///   body: AmbientBackground(child: MyScreenContent()),
/// )
/// ```
class AmbientBackground extends StatelessWidget {
  final Widget child;

  /// When false, omits the rotated S watermark — useful on busy surfaces
  /// where the watermark would compete with content. Glows still render.
  final bool showWatermark;

  const AmbientBackground({
    super.key,
    required this.child,
    this.showWatermark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Canvas
        const ColoredBox(color: AppColors.background),

        // Aurora glows — three soft radials per the CSS spec.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.76, -1.1),
                radius: 0.9,
                colors: [
                  Color(0x387A1FB0), // purple, ~.22 alpha
                  Colors.transparent,
                ],
                stops: [0.0, 0.6],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(1.1, -0.85),
                radius: 0.85,
                colors: [
                  Color(0x29E0218A), // pink, ~.16 alpha
                  Colors.transparent,
                ],
                stops: [0.0, 0.55],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.6, 1.2),
                radius: 1.0,
                colors: [
                  Color(0x1FF06000), // orange, ~.12 alpha
                  Colors.transparent,
                ],
                stops: [0.0, 0.55],
              ),
            ),
          ),
        ),

        // Faint rotated S watermark anchored to the right edge.
        if (showWatermark)
          Positioned(
            right: -120,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: 0.05,
                child: Transform.rotate(
                  angle: 0.07, // ~4°
                  child: SizedBox(
                    width: 620,
                    height: 620,
                    child: Image.asset(
                      AppAssets.sMark,
                      fit: BoxFit.contain,
                      // Fall back to the legacy logo until the rainbow
                      // S mark asset is dropped under assets/images/.
                      errorBuilder: (_, __, ___) => Image.asset(
                        AppAssets.logo,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Foreground content
        Positioned.fill(child: child),
      ],
    );
  }
}
