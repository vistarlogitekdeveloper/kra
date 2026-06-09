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

        // Tall rainbow "S" swoosh anchored along the right edge — matches
        // the Vistar Audit reference where the standalone S stands at
        // ~70% of viewport height and ~28% of width, centred vertically
        // with the right edge near (but not past) the canvas edge.
        //
        // BoxFit.contain preserves the asset's intrinsic aspect ratio so
        // the rainbow stops never stretch. No fallback to vistar_logo.png:
        // that's the wide wordmark, and silently swapping it in is what
        // caused the previous "wrong logo on screen" complaint.
        if (showWatermark)
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, c) {
                  final width = c.maxWidth * 0.28;
                  final height = c.maxHeight * 0.7;
                  return Align(
                    alignment: const Alignment(0.92, 0),
                    child: Opacity(
                      opacity: 0.22,
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: Image.asset(
                          AppAssets.sMark,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // Foreground content
        Positioned.fill(child: child),
      ],
    );
  }
}
