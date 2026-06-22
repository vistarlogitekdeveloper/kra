import 'package:flutter/material.dart';

import '../constants/app_assets.dart';
import '../constants/app_colors.dart';
import '../constants/app_gradients.dart';
import '../constants/app_strings.dart';
import 'ambient_background.dart';
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
// Splash / boot — the Vistar Premium "S-orbit" loader. Two counter-
// spinning rings around a breathing S mark, plus the wordmark and a
// ribbon progress bar. Reproduces the CSS `.s-orbit` + `.splash-bar`
// recipes from the design system spec.
// ─────────────────────────────────────────────────────────────────
class FullScreenLoadingSkeleton extends StatelessWidget {
  const FullScreenLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: AmbientBackground(
        child: SafeArea(
          child: Center(child: _SplashOrbitColumn()),
        ),
      ),
    );
  }
}

class _SplashOrbitColumn extends StatelessWidget {
  const _SplashOrbitColumn();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SOrbitLoader(),
            const SizedBox(height: 32),
            const Text(
              AppStrings.appName,
              style: TextStyle(
                fontFamily: 'BricolageGrotesque',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              AppStrings.appTagline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 3.0,
              ),
            ),
            const SizedBox(height: 28),
            const _RibbonProgressBar(),
            const SizedBox(height: 28),
            Text(
              AppStrings.companyName,
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two counter-spinning rings + a breathing S in the center. Per the
/// design spec: outer ring 1.6s forward, inner ring 2.2s reverse, S
/// breathes on 2.2s. Renders the rainbow-S asset with a graceful fallback.
class SOrbitLoader extends StatefulWidget {
  final double size;
  const SOrbitLoader({super.key, this.size = 180});

  @override
  State<SOrbitLoader> createState() => _SOrbitLoaderState();
}

class _SOrbitLoaderState extends State<SOrbitLoader>
    with TickerProviderStateMixin {
  late final AnimationController _outer;
  late final AnimationController _inner;
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _outer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _inner = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: false);
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _outer.dispose();
    _inner.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring — pink + orange arcs.
          AnimatedBuilder(
            animation: _outer,
            builder: (_, __) => Transform.rotate(
              angle: _outer.value * 2 * 3.1415926,
              child: CustomPaint(
                size: Size.square(size),
                painter: _OrbitRingPainter(
                  color1: AppColors.pink.withValues(alpha: 0.65),
                  color2: AppColors.orange.withValues(alpha: 0.40),
                  strokeWidth: 1.6,
                ),
              ),
            ),
          ),
          // Inner ring — violet + amber arcs, reversed.
          AnimatedBuilder(
            animation: _inner,
            builder: (_, __) => Transform.rotate(
              angle: -_inner.value * 2 * 3.1415926,
              child: CustomPaint(
                size: Size.square(size - 44),
                painter: _OrbitRingPainter(
                  color1: AppColors.violet.withValues(alpha: 0.65),
                  color2: AppColors.amber.withValues(alpha: 0.45),
                  strokeWidth: 1.6,
                  startAngle: 3.1415926 / 2,
                ),
              ),
            ),
          ),
          // Breathing S mark.
          ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.04).animate(
              CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pink.withValues(alpha: 0.55),
                    blurRadius: 28,
                  ),
                ],
              ),
              child: SizedBox(
                width: 96,
                height: 96,
                child: Image.asset(
                  AppAssets.sMark,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Image.asset(
                    AppAssets.logo,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints two opposite arc segments of a circle. Two stops per pass
/// reproduces the CSS `border-top-color + border-right-color` effect.
class _OrbitRingPainter extends CustomPainter {
  final Color color1;
  final Color color2;
  final double strokeWidth;
  final double startAngle;

  _OrbitRingPainter({
    required this.color1,
    required this.color2,
    required this.strokeWidth,
    this.startAngle = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth,
      strokeWidth,
      size.width - strokeWidth * 2,
      size.height - strokeWidth * 2,
    );
    final paint1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = color1;
    final paint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = color2;
    canvas.drawArc(rect, startAngle, 3.1415926 * 0.5, false, paint1);
    canvas.drawArc(rect, startAngle + 3.1415926, 3.1415926 * 0.5, false, paint2);
  }

  @override
  bool shouldRepaint(_OrbitRingPainter old) =>
      old.color1 != color1 ||
      old.color2 != color2 ||
      old.startAngle != startAngle ||
      old.strokeWidth != strokeWidth;
}

class _RibbonProgressBar extends StatefulWidget {
  const _RibbonProgressBar();

  @override
  State<_RibbonProgressBar> createState() => _RibbonProgressBarState();
}

class _RibbonProgressBarState extends State<_RibbonProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.dividerStrong,
            borderRadius: BorderRadius.circular(10),
          ),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              // -110% → +260% sweep, matching @keyframes load in the spec.
              final t = _ctrl.value;
              final dx = -1.1 + (3.7 * t); // moves -110% → +260%
              return FractionalTranslation(
                translation: Offset(dx, 0),
                child: Container(
                  width: 80,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: AppGradients.ribbon,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
