import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';

/// Friendly fallback shown by the router's [GoRouter.errorBuilder] when a
/// navigation target can't be matched (e.g. a backend deep-link points at
/// a screen that isn't built yet).
///
/// The default go_router error screen's button navigates to `/`, which
/// this app doesn't register (its routes are `/login`, `/hr/*`, …), so it
/// dead-ends. This screen instead offers a "Go to Home" button wired to a
/// route we know exists — the signed-in user's role dashboard — plus a
/// Back affordance when there's a stack to pop.
class RouteErrorScreen extends StatelessWidget {
  /// A route guaranteed to exist — the caller resolves it from auth state
  /// (the user's dashboard, or `/login` when signed out).
  final String homeRoute;
  final Object? error;

  const RouteErrorScreen({
    super.key,
    required this.homeRoute,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: AppStrings.commonBack,
                onPressed: () => context.pop(),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryPurple.withValues(alpha: 0.08),
                ),
                child: const Icon(
                  Icons.explore_off_outlined,
                  size: 52,
                  color: AppColors.primaryPurple,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                AppStrings.routeErrorTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                AppStrings.routeErrorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go(homeRoute),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text(
                    AppStrings.routeErrorGoHome,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
