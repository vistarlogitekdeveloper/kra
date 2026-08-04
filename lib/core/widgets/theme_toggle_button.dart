import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_strings.dart';
import '../theme/theme_controller.dart';

/// A one-tap dark/light theme toggle. Shows a sun in dark mode (tap → light) and
/// a moon in light mode (tap → dark). Drop it into any app bar / header; pass
/// [color] when it sits on a coloured surface (e.g. the purple home hero).
class ThemeToggleButton extends ConsumerWidget {
  final Color? color;
  const ThemeToggleButton({super.key, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark = resolveBrightness(mode) == Brightness.dark;
    return IconButton(
      icon: Icon(
        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
        color: color,
      ),
      tooltip:
          isDark ? AppStrings.themeSwitchToLight : AppStrings.themeSwitchToDark,
      visualDensity: VisualDensity.compact,
      onPressed: () =>
          ref.read(themeModeProvider.notifier).toggle(resolveBrightness(mode)),
    );
  }
}
