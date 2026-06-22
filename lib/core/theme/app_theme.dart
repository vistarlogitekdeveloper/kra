import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';

/// Single source of truth for app theming. Per the Vistar Premium spec:
///   • Bricolage Grotesque → display surfaces (titles, KPIs, brand name)
///   • Manrope             → body / labels / inputs / tables
///   • Brightness.dark, near-black `--bg` canvas, low-alpha hairlines
///   • Primary action buttons get the rainbow ribbon via
///     `BrandedPrimaryButton`; the Material default stays a quiet ghost
///     button so accidental `ElevatedButton`s don't compete with the brand
///     gradient.
///
/// To rebrand or change typography, edit ONLY this file.
class AppTheme {
  AppTheme._();

  // Kept named `lightTheme` for backwards compatibility with the bootstrap
  // call site that reads `AppTheme.lightTheme`. The theme is dark — name is
  // historical, behaviour matches the Vistar Premium spec.
  static ThemeData get lightTheme {
    // Manrope as the global default; specific display styles below override
    // to Bricolage Grotesque to match the spec's two-font system.
    final TextTheme manropeBase = GoogleFonts.manropeTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    );

    TextStyle? display(TextStyle? base, double letterSpacing) =>
        GoogleFonts.bricolageGrotesque(textStyle: base).copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: letterSpacing,
        );

    final TextTheme textTheme = manropeBase.copyWith(
      // Bricolage everywhere a Material widget reaches for a display style.
      displayLarge: display(manropeBase.displayLarge, -1.2),
      displayMedium: display(manropeBase.displayMedium, -0.8),
      displaySmall: display(manropeBase.displaySmall, -0.6),
      headlineLarge: display(manropeBase.headlineLarge, -0.6),
      headlineMedium: display(manropeBase.headlineMedium, -0.5),
      headlineSmall: display(manropeBase.headlineSmall, -0.4),
      titleLarge: display(manropeBase.titleLarge, -0.4)?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: display(manropeBase.titleMedium, -0.3)?.copyWith(
        fontWeight: FontWeight.w700,
      ),

      // Body / labels stay on Manrope.
      bodyLarge: manropeBase.bodyLarge?.copyWith(
        color: AppColors.textPrimary,
        height: 1.5,
        letterSpacing: 0.1,
      ),
      bodyMedium: manropeBase.bodyMedium?.copyWith(
        color: AppColors.textSecondary,
        height: 1.45,
        letterSpacing: 0.1,
      ),
      bodySmall: manropeBase.bodySmall?.copyWith(
        color: AppColors.textMuted,
        height: 1.4,
        letterSpacing: 0.1,
      ),
      labelLarge: manropeBase.labelLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      labelMedium: manropeBase.labelMedium?.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      labelSmall: manropeBase.labelSmall?.copyWith(
        color: AppColors.textMuted,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primaryPurple,
      canvasColor: AppColors.background,
      dividerColor: AppColors.divider,

      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryPurple,
        onPrimary: Colors.white,
        secondary: AppColors.pink,
        onSecondary: Colors.white,
        tertiary: AppColors.orange,
        error: AppColors.error,
        onError: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        surfaceContainerHighest: AppColors.surfaceElevated,
        outline: AppColors.divider,
      ),

      textTheme: textTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.bricolageGrotesque(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          letterSpacing: -0.4,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider, width: 1),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: const TextStyle(
          color: AppColors.pink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.divider, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          // Pink focus ring is part of the Vistar Premium spec.
          borderSide: const BorderSide(color: AppColors.pink, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.error, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.error, width: 1.8),
        ),
      ),

      // Material `ElevatedButton` is the quiet baseline — use
      // [BrandedPrimaryButton] for the rainbow ribbon hero CTA.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceElevated,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: const BorderSide(color: AppColors.divider),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.divider),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.pink,
          textStyle: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.pink;
          }
          return Colors.transparent;
        }),
        side: const BorderSide(color: AppColors.dividerStrong, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.pink,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.pink.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.pink);
          }
          return const IconThemeData(color: AppColors.textMuted);
        }),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceOverlay,
        contentTextStyle: GoogleFonts.manrope(
          color: AppColors.textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        modalBackgroundColor: AppColors.surface,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceOverlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: AppColors.divider),
        ),
        textStyle: GoogleFonts.manrope(
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.pink,
      ),
    );
  }
}
