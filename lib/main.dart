import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap.dart';
import 'core/constants/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/widgets/keyboard_scroll_scope.dart';
import 'core/widgets/shimmer_skeletons.dart';
import 'features/auth/presentation/providers/app_boot_provider.dart';

void main() => bootstrap(() => const ProviderScope(child: VistarApp()));

class VistarApp extends ConsumerWidget {
  const VistarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(appBootProvider);
    // Build the theme for the chosen mode. themeFor() also flips the global
    // AppColors brightness, so the whole tree repaints light/dark when this
    // rebuilds on a theme change.
    final mode = ref.watch(themeModeProvider);
    final theme = AppTheme.themeFor(resolveBrightness(mode));

    // Exhaustive pattern match rather than `.when()`: AsyncValue is sealed, so
    // the compiler proves every state is handled and a future state cannot be
    // silently dropped into a default branch.
    //
    // While the boot future is in flight we render a brand-tinted shimmer
    // splash inside a minimal MaterialApp. Once boot resolves — whether or not
    // a session was found — we hand off to the real router-driven app. That
    // avoids any flash of the login screen for an already-signed-in user.
    //
    // AsyncError falls through to the router deliberately: a failed boot means
    // "no session restored", which the router already handles by showing login.
    return switch (boot) {
      AsyncLoading() => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          title: AppStrings.appName,
          home: const FullScreenLoadingSkeleton(),
        ),
      _ => _RouterApp(theme: theme),
    };
  }
}

/// The router-driven app, as a widget CLASS rather than a `Widget _build…()`
/// method so Flutter can prune rebuilds of this subtree on its own.
class _RouterApp extends ConsumerWidget {
  const _RouterApp({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: router,
      // Screens read the GLOBAL AppColors palette (not Theme.of), and many are
      // built as `const` in the router — so a theme flip wouldn't rebuild them
      // and they'd keep the old colours. Keying the router's content subtree by
      // brightness tears it down and rebuilds every screen fresh on a toggle, so
      // the whole app repaints at once. GoRouter keeps the current route + back
      // stack (it lives in the provider), so nothing navigates away.
      // KeyboardScrollScope sits OUTSIDE the KeyedSubtree on purpose: a theme
      // flip rebuilds everything inside that subtree, and the scope owns the
      // shared ScrollController, which must survive the rebuild.
      builder: (context, child) => KeyboardScrollScope(
        child: KeyedSubtree(
          key: ValueKey(theme.brightness),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
