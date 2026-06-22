import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Brand gradient family. The "ribbon" is the Vistar Premium signature
/// accent — a left-to-right purple → magenta → pink → red → orange → amber
/// sweep at a 115° angle. Use it sparingly: primary buttons, KPI numbers
/// (via [ShaderMask]), active-nav left bar, the "on" role chip. Anything
/// larger than a thin accent or small highlight should stay on the dark
/// surface scale from [AppColors].
class AppGradients {
  AppGradients._();

  /// The full ribbon — left to right at ~115°. Stops match the CSS spec
  /// verbatim. Reach for this on signature surfaces only.
  static const LinearGradient ribbon = LinearGradient(
    begin: Alignment(-0.95, -0.4),
    end: Alignment(0.95, 0.4),
    stops: [0.00, 0.22, 0.40, 0.56, 0.70, 0.80, 0.92, 1.00],
    colors: [
      AppColors.purple,
      Color(0xFFB81FB8),
      AppColors.pink,
      Color(0xFFD11630),
      AppColors.orangeRed,
      AppColors.orange,
      AppColors.amber,
      Color(0xFFF7EE9A),
    ],
  );

  /// Softer translucent ribbon — drop behind status pills or chips where
  /// the full rainbow would scream. 90% alpha, same angle.
  static const LinearGradient ribbonSoft = LinearGradient(
    begin: Alignment(-0.95, -0.4),
    end: Alignment(0.95, 0.4),
    colors: [
      Color(0xE69B30C9),
      Color(0xE6E0218A),
      Color(0xE6F0480C),
      Color(0xE6F0C000),
    ],
  );
}
