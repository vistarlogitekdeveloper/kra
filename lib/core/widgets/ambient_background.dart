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

        // Rainbow "S" swoosh anchored right-of-centre. The bundled asset
        // (`assets/images/logo.png`) is 1536×1024 — wider than tall — so
        // we shape the box to its intrinsic 3:2 aspect ratio. Forcing a
        // tall-narrow box made BoxFit.contain letterbox the swoosh down
        // to ~280px and 22% opacity left nothing visible against the dark
        // canvas + translucent cards on top of it.
        //
        // Now: width = 45% viewport, height = width / 1.5 (matches asset).
        // Aligned at (0.95, 0) — right edge, vertically centred. Opacity
        // 0.35 so the rainbow stops actually read at this size.
        if (showWatermark)
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, c) {
                  final width = c.maxWidth * 0.45;
                  final height = width / 1.5;
                  return Align(
                    alignment: const Alignment(0.95, 0),
                    child: Opacity(
                      opacity: 0.35,
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
