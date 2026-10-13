import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/employee_deletion_impact.dart';

/// Confirmation for a PERMANENT employee delete, showing what it removes.
///
/// Built around one asymmetry: the counts fall into three groups that mean
/// different things, and summing them would hide the one that matters.
///
///   * their own records — expected, and the reason the user is here;
///   * **records belonging to other employees** — the reviews this person rated
///     for their team, the feeds they entered. Deleting a manager takes their
///     whole team's ratings with them, and nothing about the word "delete"
///     suggests that. Shown with its own heading and an explanation;
///   * reporting lines — reports are DETACHED, not deleted, which reads as
///     alarming unless it says so.
///
/// Confirm is deliberately a plain destructive button rather than type-to-
/// confirm: the preview is the safeguard, and an extra ritual on top of an
/// already-explicit two-step tends to be clicked through rather than read.
class PurgeEmployeeDialog extends StatelessWidget {
  final EmployeeDeletionImpact impact;

  const PurgeEmployeeDialog({super.key, required this.impact});

  /// Returns true only when the user explicitly confirmed.
  static Future<bool?> show(
    BuildContext context, {
    required EmployeeDeletionImpact impact,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (_) => PurgeEmployeeDialog(impact: impact),
      );

  @override
  Widget build(BuildContext context) {
    final who = [
      if ((impact.name ?? '').isNotEmpty) impact.name!,
      if ((impact.employeeCode ?? '').isNotEmpty) '(${impact.employeeCode})',
    ].join(' ');

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Row(
        children: [
          Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              AppStrings.employeePurgeTitle,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (who.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  who,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            const Text(
              AppStrings.employeePurgeIrreversible,
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),

            // Nothing to enumerate — say that plainly instead of printing a
            // list of zeroes, which reads as though something was miscounted.
            if (impact.isEmpty)
              Text(
                AppStrings.employeePurgeNothingElse,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),

            if (impact.ownTotal > 0) ...[
              const _GroupHeading(AppStrings.employeePurgeOwnHeading),
              _Line(impact.reviewsAsEmployee, 'review', 'reviews'),
              _Line(impact.assignmentsOwn, 'KRA assignment', 'KRA assignments'),
              _Line(impact.monthlyReviews, 'monthly sheet', 'monthly sheets'),
            ],

            // The surprising group. Emphasised, and explained — the figures
            // alone do not convey that this is somebody else's data.
            if (impact.marksOnOthersTotal > 0) ...[
              const SizedBox(height: 14),
              const _GroupHeading(
                AppStrings.employeePurgeOthersHeading,
                emphasised: true,
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  AppStrings.employeePurgeOthersWhy,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.error,
                  ),
                ),
              ),
              _Line(impact.reviewsAsManager, 'review they rated as manager',
                  'reviews they rated as manager'),
              _Line(impact.assignmentsMade, 'KRA they assigned',
                  'KRAs they assigned'),
              _Line(impact.hrFeedsEntered, 'HR feed entry', 'HR feed entries'),
              _Line(impact.accountsFeedsEntered, 'Accounts feed entry',
                  'Accounts feed entries'),
              _Line(
                  impact.opsFeedsEntered, 'Ops feed entry', 'Ops feed entries'),
              _Line(impact.opsScopesAssigned, 'ops-scope assignment',
                  'ops-scope assignments'),
            ],

            // Detached, not deleted — stated as such so it does not read as
            // another thing being destroyed.
            if (impact.subordinates > 0) ...[
              const SizedBox(height: 14),
              const _GroupHeading(AppStrings.employeePurgeDetachHeading),
              Text(
                AppStrings.employeePurgeDetaches(impact.subordinates),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text(AppStrings.employeePurgeConfirm),
        ),
      ],
    );
  }
}

class _GroupHeading extends StatelessWidget {
  final String text;
  final bool emphasised;
  const _GroupHeading(this.text, {this.emphasised = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
            color: emphasised ? AppColors.error : AppColors.textMuted,
          ),
        ),
      );
}

/// One count, hidden entirely when zero.
///
/// A dialog listing "0 HR feed entries" alongside real figures buries the
/// numbers that matter in ones that do not.
class _Line extends StatelessWidget {
  final int count;
  final String singular;
  final String plural;
  const _Line(this.count, this.singular, this.plural);

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(color: AppColors.textSecondary)),
          Expanded(
            child: Text(
              AppStrings.countOf(count, singular, plural),
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
