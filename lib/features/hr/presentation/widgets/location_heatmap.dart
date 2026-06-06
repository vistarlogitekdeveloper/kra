import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../data/models/hr_dashboard_models.dart';
import '../providers/hr_dashboard_providers.dart';

/// Location × month heatmap of average review scores. Each row is a
/// project location; each cell is one month, coloured by the cell's
/// `avgPct`. Empty cells (no rated reviews) render in muted divider grey.
///
/// Scoped to the active cycle — caller passes the cycle id, the widget
/// uses [hrLocationHeatmapProvider] to fetch the matrix and renders its
/// own loading / error / empty states.
class LocationHeatmap extends ConsumerWidget {
  final String cycleId;
  const LocationHeatmap({super.key, required this.cycleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hrLocationHeatmapProvider(cycleId));
    return async.when(
      loading: _buildLoading,
      error: (e, _) => _buildError(e.toString(), ref),
      data: (heatmap) => _buildData(context, heatmap),
    );
  }

  Widget _buildLoading() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShimmerBox(height: 14, width: 160, borderRadius: 6),
          SizedBox(height: 14),
          ShimmerBox(height: 28, borderRadius: 8),
          SizedBox(height: 10),
          ShimmerBox(height: 28, borderRadius: 8),
          SizedBox(height: 10),
          ShimmerBox(height: 28, borderRadius: 8),
        ],
      ),
    );
  }

  Widget _buildError(String message, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.invalidate(hrLocationHeatmapProvider(cycleId)),
            child: const Text(
              AppStrings.commonRetry,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildData(BuildContext context, HrLocationHeatmap heatmap) {
    if (heatmap.locations.isEmpty || heatmap.months.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Text(
          'No heatmap data yet',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderRow(months: heatmap.months),
                const SizedBox(height: 6),
                for (final loc in heatmap.locations) ...[
                  _LocationRow(
                    location: loc,
                    months: heatmap.months,
                    onTap: () =>
                        _showLocationSheet(context, loc, heatmap.months),
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _Legend(),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final List<HrHeatmapMonth> months;
  const _HeaderRow({required this.months});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 110),
        for (final m in months)
          SizedBox(
            width: 56,
            child: Text(
              m.label.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
      ],
    );
  }
}

class _LocationRow extends StatelessWidget {
  final HrHeatmapLocation location;
  final List<HrHeatmapMonth> months;
  final VoidCallback onTap;
  const _LocationRow({
    required this.location,
    required this.months,
    required this.onTap,
  });

  HrHeatmapCell? _cellFor(String monthId) {
    for (final c in location.cells) {
      if (c.monthId == monthId) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(
                location.locationName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final m in months)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                child: _HeatCell(cell: _cellFor(m.id)),
              ),
          ],
        ),
      ),
    );
  }
}

HrHeatmapCell? _cellForMonth(HrHeatmapLocation location, String monthId) {
  for (final c in location.cells) {
    if (c.monthId == monthId) return c;
  }
  return null;
}

Future<void> _showLocationSheet(
  BuildContext context,
  HrHeatmapLocation location,
  List<HrHeatmapMonth> months,
) {
  // Cycle average across the cells that actually have data.
  double? cycleAvg;
  int totalReviews = 0;
  final scored = location.cells.where((c) => c.avgPct != null).toList();
  if (scored.isNotEmpty) {
    cycleAvg =
        scored.map((c) => c.avgPct!).reduce((a, b) => a + b) / scored.length;
  }
  for (final c in location.cells) {
    totalReviews += c.reviewCount;
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                location.locationName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                cycleAvg == null
                    ? '$totalReviews ${AppStrings.hrHeatmapReviewsCount}'
                    : '${AppStrings.hrHeatmapAverage}: '
                        '${cycleAvg.toStringAsFixed(1)}% '
                        '· $totalReviews ${AppStrings.hrHeatmapReviewsCount}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                AppStrings.hrHeatmapMonthlyBreakdown,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              for (final m in months) ...[
                _MonthBreakdownTile(
                  month: m,
                  cell: _cellForMonth(location, m.id),
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    context.push(AppRoutes.hrEmployees);
                  },
                  icon: const Icon(Icons.groups_outlined, size: 18),
                  label: const Text(
                    AppStrings.hrHeatmapViewEmployees,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _MonthBreakdownTile extends StatelessWidget {
  final HrHeatmapMonth month;
  final HrHeatmapCell? cell;
  const _MonthBreakdownTile({required this.month, required this.cell});

  @override
  Widget build(BuildContext context) {
    final pct = cell?.avgPct;
    final reviews = cell?.reviewCount ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              month.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$reviews ${AppStrings.hrHeatmapReviewsCount}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: pct == null
                  ? AppColors.textMuted
                  : AppColors.primaryPurple,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  final HrHeatmapCell? cell;
  const _HeatCell({required this.cell});

  /// Linear blend from low (purple-light) → high (success green) so the
  /// gradient reads as "more is better" without leaning on red anywhere.
  Color _colourFor(double pct) {
    final t = (pct / 100).clamp(0.0, 1.0);
    if (t < 0.5) {
      return Color.lerp(
        AppColors.primaryPurple.withValues(alpha: 0.15),
        AppColors.accentYellow.withValues(alpha: 0.65),
        t * 2,
      )!;
    }
    return Color.lerp(
      AppColors.accentYellow.withValues(alpha: 0.65),
      AppColors.success,
      (t - 0.5) * 2,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final pct = cell?.avgPct;
    final isEmpty = pct == null || (cell?.reviewCount ?? 0) == 0;
    final colour =
        isEmpty ? AppColors.divider.withValues(alpha: 0.7) : _colourFor(pct);
    final label = isEmpty ? '—' : pct.toStringAsFixed(0);
    final textColour = isEmpty || pct < 50
        ? AppColors.textPrimary
        : Colors.white;

    return Tooltip(
      message: cell == null
          ? 'No data'
          : '${cell!.monthLabel}: ${pct == null ? "—" : "${pct.toStringAsFixed(1)}%"} '
              '(${cell!.reviewCount} reviews)',
      child: Container(
        width: 50,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: textColour,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Low',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 110,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: [
                AppColors.primaryPurple.withValues(alpha: 0.15),
                AppColors.accentYellow.withValues(alpha: 0.65),
                AppColors.success,
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'High',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
