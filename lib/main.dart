import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/shimmer_skeletons.dart';
import 'features/auth/presentation/providers/app_boot_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: VistarApp()));
}

class VistarApp extends ConsumerWidget {
  const VistarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(appBootProvider);

    // While the boot future is in flight we render a brand-tinted
    // shimmer splash inside a minimal MaterialApp. Once boot resolves
    // (regardless of whether a session was found), we hand off to the
    // real router-driven MaterialApp. This avoids any flash of the
    // login screen for already-logged-in users.
    return boot.when(
      loading: () => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        title: AppStrings.appName,
        home: const FullScreenLoadingSkeleton(),
      ),
      error: (_, __) => _buildRouterApp(ref),
      data: (_) => _buildRouterApp(ref),
    );
  }

  Widget _buildRouterApp(WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}
