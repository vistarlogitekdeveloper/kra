import 'package:flutter/material.dart';

import '../constants/app_assets.dart';
import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import 'shimmer_box.dart';

/// Pre-built shimmer skeletons for the screens this app will gain.
/// They live here so a screen can drop in a placeholder with one line:
///
///   if (isLoading) return const DashboardCardSkeleton();
///
/// Each skeleton's geometry roughly matches the real widget it replaces,
/// so there is no layout jump when the data arrives.

// ─────────────────────────────────────────────────────────────────
// Dashboard card — used on role landing pages (KRA totals, score, etc.)
// ─────────────────────────────────────────────────────────────────
class DashboardCardSkeleton extends StatelessWidget {
  const DashboardCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerBox(width: 40, height: 40, borderRadius: 12),
              SizedBox(width: 12),
              Expanded(child: ShimmerBox(height: 14, borderRadius: 6)),
            ],
          ),
          SizedBox(height: 18),
          ShimmerBox(height: 28, width: 120, borderRadius: 8),
          SizedBox(height: 10),
          ShimmerBox(height: 12, borderRadius: 6),
          SizedBox(height: 6),
          ShimmerBox(height: 12, width: 180, borderRadius: 6),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Generic list row — used on KRA lists, user lists, etc.
// ─────────────────────────────────────────────────────────────────
class ListItemSkeleton extends StatelessWidget {
  const ListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: const Row(
        children: [
          ShimmerBox(width: 44, height: 44, borderRadius: 22),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(height: 14, borderRadius: 6),
                SizedBox(height: 8),
                ShimmerBox(height: 12, width: 140, borderRadius: 6),
              ],
            ),
          ),
          SizedBox(width: 12),
          ShimmerBox(width: 56, height: 24, borderRadius: 12),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Profile header — avatar circle + 2 text lines
// ─────────────────────────────────────────────────────────────────
class ProfileHeaderSkeleton extends StatelessWidget {
  const ProfileHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Row(
        children: [
          ShimmerBox(width: 64, height: 64, borderRadius: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(height: 16, borderRadius: 8),
                SizedBox(height: 8),
                ShimmerBox(height: 13, width: 160, borderRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// KRA table — header row + 4 data rows
// ─────────────────────────────────────────────────────────────────
class KraTableSkeleton extends StatelessWidget {
  const KraTableSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFAF5FB),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 4, child: ShimmerBox(height: 12, borderRadius: 6)),
                SizedBox(width: 8),
                Expanded(flex: 1, child: ShimmerBox(height: 12, borderRadius: 6)),
                SizedBox(width: 8),
                Expanded(flex: 1, child: ShimmerBox(height: 12, borderRadius: 6)),
              ],
            ),
          ),
          for (int i = 0; i < 4; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppColors.divider.withValues(alpha: 0.6),
                  ),
                ),
              ),
              child: const Row(
                children: [
                  Expanded(
                      flex: 4,
                      child: ShimmerBox(height: 14, borderRadius: 6)),
                  SizedBox(width: 8),
                  Expanded(
                      flex: 1,
                      child: ShimmerBox(height: 14, borderRadius: 6)),
                  SizedBox(width: 8),
                  Expanded(
                      flex: 1,
                      child: ShimmerBox(height: 14, borderRadius: 6)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Splash / boot — logo + 3 shimmer lines, no spinner
// ─────────────────────────────────────────────────────────────────
class FullScreenLoadingSkeleton extends StatelessWidget {
  const FullScreenLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentOrange
                                .withValues(alpha: 0.18),
                            blurRadius: 30,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        AppAssets.logo,
                        height: 92,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 92,
                          width: 92,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const ShimmerBox(height: 14, width: 220, borderRadius: 7),
                    const SizedBox(height: 10),
                    const ShimmerBox(height: 14, borderRadius: 7),
                    const SizedBox(height: 10),
                    const ShimmerBox(height: 14, width: 160, borderRadius: 7),
                    const SizedBox(height: 36),
                    const Text(
                      AppStrings.companyName,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
