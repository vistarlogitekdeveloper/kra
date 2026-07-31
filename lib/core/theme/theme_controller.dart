import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage_service.dart';

/// App-wide theme mode (light / dark / system), persisted to secure storage.
///
/// Starts on [ThemeMode.dark] (the app's historical look) and overrides it once
/// the stored preference loads, so there's no flash of the wrong theme for a
/// returning user beyond the first frame.
class ThemeModeController extends StateNotifier<ThemeMode> {
  final SecureStorageService _storage;
  ThemeModeController(this._storage) : super(ThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    final mode = _fromString(await _storage.readThemeMode());
    if (mode != null && mounted) state = mode;
  }

  /// Set + persist an explicit mode.
  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _storage.writeThemeMode(mode.name);
  }

  /// Flip between light and dark (a `system` state resolves to its opposite).
  Future<void> toggle(Brightness current) =>
      set(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  static ThemeMode? _fromString(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }
}

/// The active theme mode. Watch this at the app root to pick the theme and in
/// the toggle UI to reflect + change it.
final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(secureStorageProvider));
});

/// Resolves [mode] to a concrete brightness — `system` reads the platform.
Brightness resolveBrightness(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return Brightness.light;
    case ThemeMode.dark:
      return Brightness.dark;
    case ThemeMode.system:
      return WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }
}
