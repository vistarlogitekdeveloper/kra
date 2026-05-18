import 'package:flutter/material.dart';

/// Vistar brand colors — extracted from the official logo.
/// These are the ONLY color values the app should use directly.
/// Everywhere else should reference [AppTheme] from theme.dart.
class AppColors {
  AppColors._();

  // Primary brand purple (the "Vistar" wordmark color)
  static const Color primaryPurple = Color(0xFF6B1F7C);
  static const Color primaryPurpleDark = Color(0xFF4A1456);
  static const Color primaryPurpleLight = Color(0xFF8E3CA0);

  // Accent flame colors (from the swoosh)
  static const Color accentRed = Color(0xFFE63946);
  static const Color accentOrange = Color(0xFFFF6B1A);
  static const Color accentYellow = Color(0xFFFFB800);

  // Neutrals
  static const Color background = Color(0xFFFAF7FB);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textMuted = Color(0xFFAAAAAA);
  static const Color divider = Color(0xFFEAE5EE);
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF2E7D32);

  // Pale purple-tinted surface — used by status pills and KPI card
  // backgrounds where `primaryPurple.withValues(alpha: 0.10)` would be
  // visually identical but can't be `const`-evaluated. Pre-composited
  // over a white surface, so it round-trips cleanly across screenshots.
  static const Color primaryPurpleSurface = Color(0xFFF1ECF4);

  // The signature Vistar gradient (used sparingly, on hero elements only)
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      primaryPurple,
      accentRed,
      accentOrange,
      accentYellow,
    ],
    stops: [0.0, 0.4, 0.7, 1.0],
  );

  // Subtle background gradient for the login screen
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFAF7FB),
      Color(0xFFF5EDF7),
    ],
  );
}
