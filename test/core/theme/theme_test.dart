import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/app_colors.dart';
import 'package:vistar_app/core/theme/theme_controller.dart';

/// The light/dark theme flips the app-wide [AppColors] surface/text tokens.
/// Lock the resolution so a token can't quietly stop being theme-aware.
void main() {
  // Leave the global palette dark for any other tests in this isolate.
  tearDown(() => AppColors.setBrightness(Brightness.dark));

  group('AppColors theme resolution', () {
    test('surface/text/divider tokens differ between light and dark', () {
      AppColors.setBrightness(Brightness.dark);
      expect(AppColors.isLight, isFalse);
      final darkBg = AppColors.background;
      final darkText = AppColors.textPrimary;
      final darkSurface = AppColors.surface;

      AppColors.setBrightness(Brightness.light);
      expect(AppColors.isLight, isTrue);
      expect(AppColors.background, isNot(darkBg));
      expect(AppColors.textPrimary, isNot(darkText));
      expect(AppColors.surface, isNot(darkSurface));
    });

    test('brand + semantic colours are the same in both themes', () {
      AppColors.setBrightness(Brightness.dark);
      const purpleDark = AppColors.primaryPurple;
      const errorDark = AppColors.error;
      AppColors.setBrightness(Brightness.light);
      expect(AppColors.primaryPurple, purpleDark);
      expect(AppColors.error, errorDark);
    });
  });

  group('theme wiring', () {
    test('resolveBrightness maps explicit modes', () {
      expect(resolveBrightness(ThemeMode.light), Brightness.light);
      expect(resolveBrightness(ThemeMode.dark), Brightness.dark);
    });
  });
}
