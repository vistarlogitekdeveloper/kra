import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_gradients.dart';
import '_formatters.dart';

/// Big-number stat card for the HR home screen.
/// Used in a 2x2 (or 1x4) grid; sizes itself to fill the column.
///
/// Vistar Premium signature: the headline number wears the ribbon gradient
/// via a [ShaderMask] (spec's `background-clip:text` translated to Flutter),
/// and a faint "S" accent sits at the bottom-right corner per the spec's
/// `.card .corner-s` rule.
class OverviewStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconBg;
  final Color iconFg;
  final double? trendPercent;

  /// Use [valueColor] when the brand wants the number itself tinted. Pass
  /// `null` (the default) to wear the ribbon gradient instead — the right
  /// choice for the standard four-stat HR home grid.
  final Color? valueColor;

  const OverviewStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconBg = AppColors.surfaceElevated,
    this.iconFg = AppColors.pink,
    this.trendPercent,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        // --surface gradient per the Vistar Premium spec.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.surfaceElevated.withValues(alpha: 0.7),
            AppColors.surface.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Corner S accent — faint, per spec.
          Positioned(
            right: -26,
            bottom: -30,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.05,
                child: SizedBox(
                  width: 120,
                  height: 120,
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
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.pink.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: iconFg, size: 20),
                  ),
                  const Spacer(),
                  if (trendPercent != null) _TrendPill(value: trendPercent!),
                ],
              ),
              const SizedBox(height: 14),
              _RibbonValue(value: value, overrideColor: valueColor),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Renders the KPI number with the rainbow ribbon shader unless the caller
/// passes an explicit [overrideColor]. Bricolage Grotesque per the spec.
class _RibbonValue extends StatelessWidget {
  final String value;
  final Color? overrideColor;

  const _RibbonValue({required this.value, required this.overrideColor});

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontFamily: 'BricolageGrotesque',
      fontSize: 30,
      fontWeight: FontWeight.w800,
      color: overrideColor ?? Colors.white,
      letterSpacing: -0.6,
      height: 1.0,
    );

    final text = Text(value, style: textStyle);

    if (overrideColor != null) return text;

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => AppGradients.ribbon.createShader(rect),
      child: text,
    );
  }
}

class _TrendPill extends StatelessWidget {
  final double value;
  const _TrendPill({required this.value});

  @override
  Widget build(BuildContext context) {
    final positive = value >= 0;
    final color = positive ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            color: color,
            size: 12,
          ),
          const SizedBox(width: 2),
          Text(
            HrFormatters.signedPercent(value)
                .replaceAll('+', '')
                .replaceAll('−', ''),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
