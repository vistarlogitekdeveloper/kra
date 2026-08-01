import 'package:flutter/material.dart';

/// Vistar Premium colour tokens — see [docs/DESIGN_SYSTEM_PROMPT.md] for the
/// source of truth. The public API of this class is intentionally stable
/// (existing references like `AppColors.background`, `AppColors.surface`,
/// `AppColors.textPrimary` still resolve) so flipping the dark-theme values
/// here cascades to every screen without a sweep through ~114 widget files.
///
/// Token map (CSS spec → Dart):
///   --bg          #070611  →  [background]
///   --bg2         #0B0A18  →  [backgroundDeep]
///   --surface     #110F1E  →  [surface]          (cards, app bars)
///   --surface2    #16142A  →  [surfaceElevated]  (hover, raised panels)
///   --surface3    #1D1A33  →  [surfaceOverlay]   (popups, picker rows)
///   --line        rgba(.., .08)  →  [divider]
///   --line2       rgba(.., .13)  →  [dividerStrong]
///   --txt         #F2EEFB  →  [textPrimary]
///   --txt2        #B9B2D6  →  [textSecondary]
///   --txt3        #7E769B  →  [textMuted]
///   --ok          #34D399  →  [success]
///   --warn        #FBBF24  →  [warning]
///   --bad         #FB6F84  →  [error]
///   --info        #5BA8FF  →  [info]
///
/// The "ribbon" gradient lives in [AppGradients] so it can be const-shared.
class AppColors {
  AppColors._();

  // ───── Brand ribbon stops (use the full ribbon via AppGradients, not these
  // flat values, for anything larger than a thin accent line) ─────
  static const Color purple = Color(0xFF7A1FB0);
  static const Color violet = Color(0xFF9B30C9);
  static const Color magenta = Color(0xFFC018C0);
  static const Color pink = Color(0xFFE0218A);
  static const Color red = Color(0xFFC8102E);
  static const Color orangeRed = Color(0xFFF0480C);
  static const Color orange = Color(0xFFF06000);
  static const Color amber = Color(0xFFF0C000);
  static const Color yellow = Color(0xFFF0E060);

  // ───── Backwards-compatible "primary purple" family ─────
  //
  // The pre-Premium app referenced `primaryPurple` everywhere. Mapped to
  // the ribbon's purple stop so existing widgets stay coherent with the
  // new palette without a sweeping rename.
  static const Color primaryPurple = purple;
  static const Color primaryPurpleLight = violet;
  static const Color primaryPurpleDark = Color(0xFF5A0F80);

  // ───── Backwards-compatible accent aliases ─────
  static const Color accentRed = red;
  static const Color accentOrange = orange;
  static const Color accentYellow = amber;

  /// Active theme brightness. The surface / text / divider tokens below are
  /// getters that resolve against it, so flipping this (via [setBrightness]) and
  /// rebuilding repaints the whole app light or dark. Brand + semantic colours
  /// are identical in both themes and stay `const`.
  static Brightness _brightness = Brightness.dark;
  static Brightness get brightness => _brightness;
  static bool get isLight => _brightness == Brightness.light;
  static void setBrightness(Brightness b) => _brightness = b;
  static Color _t(Color dark, Color light) => isLight ? light : dark;

  // ───── Surfaces ─────
  static Color get background =>
      _t(const Color(0xFF070611), const Color(0xFFF5F4FA));
  static Color get backgroundDeep =>
      _t(const Color(0xFF0B0A18), const Color(0xFFFFFFFF));
  static Color get surface =>
      _t(const Color(0xFF110F1E), const Color(0xFFFFFFFF));
  static Color get surfaceElevated =>
      _t(const Color(0xFF16142A), const Color(0xFFF0EEF8));
  static Color get surfaceOverlay =>
      _t(const Color(0xFF1D1A33), const Color(0xFFEAE7F4));

  // ───── Text ─────
  // Light-mode text runs darker than a literal palette inversion so it reads
  // with real contrast on the near-white surfaces (the muted grey especially).
  static Color get textPrimary =>
      _t(const Color(0xFFF2EEFB), const Color(0xFF120F1E));
  static Color get textSecondary =>
      _t(const Color(0xFFB9B2D6), const Color(0xFF362F4A));
  static Color get textMuted =>
      _t(const Color(0xFF7E769B), const Color(0xFF554F6C));

  // ───── Lines / dividers ─────
  static Color get divider =>
      _t(const Color(0x14FFFFFF), const Color(0x14000000));
  static Color get dividerStrong =>
      _t(const Color(0x21FFFFFF), const Color(0x1F000000));

  // ───── Semantic ─────
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color error = Color(0xFFFB6F84);
  static const Color info = Color(0xFF5BA8FF);

  /// Pale-purple tinted surface for status pills + KPI fills. Pre-comped
  /// over the dark canvas so it can stay `const`. (Was a pale lavender on
  /// the light theme; remapped to the elevated surface for parity.)
  static Color get primaryPurpleSurface => surfaceElevated;

  /// Subtle dark gradient used on splash + auth backgrounds. The bright
  /// signature treatment is [AppGradients.ribbon] — this gradient is the
  /// quiet canvas underneath.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF070611),
      Color(0xFF0B0A18),
    ],
  );
}
