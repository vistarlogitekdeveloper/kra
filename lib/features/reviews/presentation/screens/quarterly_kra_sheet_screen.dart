import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_gradients.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/enums/kra_reviewer.dart';
import '../../../../core/utils/proof_file_saver.dart';
import '../../../../core/widgets/adaptive_leading.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/workspace_drawer.dart';
import '../../../auth/data/models/user.dart';
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/monthly_kra_row.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/review_stage.dart';
import '../../data/models/row_score.dart';
import '../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../data/models/stage_record.dart';
import '../../data/repositories/monthly_review_repository.dart';
import '../providers/kra_reviewer_map_provider.dart';
import '../providers/monthly_review_providers.dart';

/// Content type for a proof attachment, from its extension.
///
/// Any file type is accepted (Excel, Word, PowerPoint, images, PDF, …) — the
/// picker no longer restricts extensions. The stored mime is what lets a viewer
/// open it with the right handler; anything unrecognised still uploads fine and
/// falls back to a generic binary type.
String _mimeFor(String fileName) {
  final parts = fileName.toLowerCase().split('.');
  final ext = parts.length > 1 ? parts.last : '';
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'pdf':
      return 'application/pdf';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'csv':
      return 'text/csv';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'doc':
      return 'application/msword';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'txt':
      return 'text/plain';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}

/// Brand colour that identifies a KRA's single Review-cycle reviewer, so the
/// name badge and the month cell read as the same owner at a glance.
Color _reviewerColor(KraReviewer r) {
  switch (r) {
    case KraReviewer.reportingManager:
      return AppColors.primaryPurple;
    case KraReviewer.hr:
      return AppColors.info;
    case KraReviewer.accounts:
      return AppColors.accentOrange;
  }
}

/// Icon that identifies a reviewer group on the sheet.
IconData _reviewerIcon(KraReviewer r) {
  switch (r) {
    case KraReviewer.reportingManager:
      return Icons.manage_accounts_rounded;
    case KraReviewer.hr:
      return Icons.badge_rounded;
    case KraReviewer.accounts:
      return Icons.account_balance_rounded;
  }
}

/// Quarterly KRA sheet for one employee — models the "KRA for … .xlsx"
/// reference: every KRA across the 3 months of a quarter with Self + Manager
/// scores, a quarter average, and the payout. The employee edits their own
/// Self scores; the reporting manager edits Manager scores; admins/HR can
/// edit either. Pass [employeeId] to view someone else; omit it for the
/// signed-in user's own sheet.
class QuarterlyKraSheetScreen extends ConsumerStatefulWidget {
  final String? employeeId;
  const QuarterlyKraSheetScreen({super.key, this.employeeId});

  @override
  ConsumerState<QuarterlyKraSheetScreen> createState() =>
      _QuarterlyKraSheetScreenState();
}

class _QuarterlyKraSheetScreenState
    extends ConsumerState<QuarterlyKraSheetScreen> {
  ReviewPeriod? _anchor;
  bool _saving = false;

  /// Locally-attached proof files, one per KRA, keyed by "reviewId|rowId".
  /// Kept only for this session — there's no upload endpoint yet, so the file
  /// itself doesn't survive a reload. The Reason and Proof note DO persist
  /// (they ride on the employee's SELF_RATING score for the KRA).
  final Map<String, ({String name, Uint8List? bytes})> _proofFiles = {};

  RowScore? _currentScore(
      MonthlyReview review, String rowId, ReviewStage stage) {
    for (final row in review.rows) {
      if (row.id == rowId) return row.scoreFor(stage);
    }
    return null;
  }

  /// Ensures EVERY KRA row carries its single assigned reviewer, so scoring, the
  /// Review cell and the evidence slots all treat the KRA as owned by exactly
  /// one reviewer — never an average of three.
  ///
  /// Resolution order PER ROW, chosen so it reads IDENTICALLY for every login:
  ///   1. the row's OWN reviewer, straight from the backend — the review
  ///      endpoint is role-agnostic, so this is the same value whoever is
  ///      signed in. It MUST win, or the sheet would show different reviewers to
  ///      Accounts vs HR-admin (the template/assignment fetch below is gated to
  ///      HR_ADMIN/ADMIN, so it is empty for everyone else). The backend keeps
  ///      this value fresh from the template on read.
  ///   2. the template's assignment, by normalised KRA name — a best-effort
  ///      fallback that only loads for HR-tier roles, so it only fills a row the
  ///      backend left blank;
  ///   3. the template's assignment by POSITION (the Nth KRA);
  ///   4. default to the Reporting Manager — the relationship every employee
  ///      has — so a KRA is never left unassigned.
  MonthlyReview? _applyReviewerMap(
      MonthlyReview? r, KraReviewerAssignment map) {
    if (r == null) return r;
    // Match the template's ordering so position-based fallback lines up.
    final ordered = [...r.rows]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final rows = <MonthlyKraRow>[
      for (var i = 0; i < ordered.length; i++)
        () {
          final row = ordered[i];
          final reviewer = row.reviewerGroup ??
              map.byName[kraNameKey(row.name)] ??
              (i < map.byOrder.length ? map.byOrder[i] : null) ??
              KraReviewer.reportingManager;
          return row.reviewerGroup == reviewer
              ? row
              : row.copyWith(reviewerGroup: reviewer);
        }(),
    ];
    return r.copyWith(rows: rows);
  }

  double? _pct(MonthlyReview? r, String rowId, ReviewStage stage) {
    if (r == null) return null;
    for (final row in r.rows) {
      if (row.id != rowId) continue;
      final s = row.scoreFor(stage);
      if (s?.value != null && row.maxScore > 0) {
        return (s!.value! / row.maxScore) * 100;
      }
      return null;
    }
    return null;
  }

  // Self rating: editable ONLY by the employee themselves (their own sheet).
  // Admins, HR and managers can view it but not change someone's self score.
  //
  // Every gate below ALSO requires the month's review to still be open. That
  // check is not cosmetic: the backend rejects a save against a finished
  // review with 409 RES_002 ("Review is completed; scores are locked."). A
  // gate that only asks "who are you?" renders an edit affordance on a locked
  // month, opens the rating sheet, and fails only *after* the user has picked
  // a value. Each month in the quarter locks independently, so the check is
  // per-review — never per-sheet.
  bool _canEditSelf(MonthlyReview r, ReviewScope? scope) {
    if (scope == null || r.isComplete) return false;
    return scope.userId == r.employeeId;
  }

  // Manager rating: editable ONLY by this employee's own reporting manager.
  //
  // This is a RELATIONSHIP, not a role. EVERY employee has a reporting manager
  // — managers report to senior managers, and HR/admins report to someone too
  // — so the rater's own role is irrelevant: whoever this review's `managerId`
  // points at is the one who rates it. Gating on a manager-tier role used to
  // lock out a perfectly valid reporting manager who happened to be HR/admin.
  // Still excludes the employee themselves and anyone else's manager.
  bool _canEditManager(MonthlyReview r, ReviewScope? scope) {
    if (scope == null || r.isComplete) return false;
    return r.managerId != null && r.managerId == scope.userId;
  }

  // The three Review-cycle raters are entered in parallel. Two are gated by
  // ROLE (HR, Finance); the reporting-manager one stays a RELATIONSHIP (above).
  //   * HR rating       → HR / HR_ADMIN
  //   * Finance rating  → FINANCE
  bool _canEditHr(MonthlyReview r, ReviewScope? scope) =>
      scope != null &&
      !r.isComplete &&
      (scope.role == UserRole.hr || scope.role == UserRole.hrAdmin);
  bool _canEditFinance(MonthlyReview r, ReviewScope? scope) =>
      scope != null && !r.isComplete && scope.role == UserRole.finance;

  // Management review (cycle 3) — HR either approves the Review average or, on
  // rework, overrides it per KRA. Done by HR_ADMIN / ADMIN.
  //
  // Split in two on purpose. [_hasManagementRole] is the ROLE alone, with no
  // lock check: it gates the sheet-level lock / reopen actions, and *reopening*
  // is precisely the action you need on a finished quarter — folding
  // `!isComplete` into it would remove the only way back out of a locked
  // review. [_canEditManagement] adds the lock and gates per-KRA score entry.
  bool _hasManagementRole(ReviewScope? scope) =>
      scope != null &&
      (scope.role == UserRole.hrAdmin || scope.role == UserRole.admin);

  bool _canEditManagement(MonthlyReview r, ReviewScope? scope) =>
      _hasManagementRole(scope) && !r.isComplete;

  Future<void> _editCell({
    required MonthlyReview review,
    required String rowId,
    required double maxScore,
    required ReviewStage stage,
    required double? currentPct,
    required String kraName,
    required String monthLabel,
  }) async {
    // The reporting manager moderates a self-assessment; they never inflate it.
    // So their score for a KRA is capped at the employee's own score for that
    // same KRA and month. Enforced here (the ceiling passed into the sheet) and
    // again on commit inside the sheet.
    double? capPct;
    String? capNote;
    if (stage == ReviewStage.reportingManagerRating) {
      final selfValue = _currentScore(review, rowId, ReviewStage.selfRating)?.value;
      if (selfValue == null) {
        // Nothing to moderate yet. Rating first would let the manager set the
        // ceiling for the employee's own rating, which inverts the order.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.sheetCapNoSelfRating)),
          );
        }
        return;
      }
      capPct = (selfValue / maxScore * 100).clamp(0, 100).toDouble();
      capNote = '${AppStrings.sheetCapPrefix} ${capPct.round()}%';
    }

    // Accessible rating entry: a slider + one-tap presets in a bottom sheet.
    // Nothing is written until Save is tapped — presets only set the value.
    final result = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _RatingSheet(
        kraName: kraName,
        monthLabel: monthLabel,
        stageLabel: stage.label,
        currentPct: currentPct,
        maxPct: capPct,
        capNote: capNote,
      ),
    );
    if (result == null || result < 0) return;

    setState(() => _saving = true);
    try {
      final value = result / 100 * maxScore;
      // Preserve any Reason / Proof note already on this score — editing the
      // number must not wipe the employee's justification.
      final current = _currentScore(review, rowId, stage);
      await ref.read(monthlyReviewRepositoryProvider).saveStageScores(
        review.id,
        stage,
        rowScores: {
          rowId: RowScore(
            value: value,
            remark: current?.remark,
            proofNote: current?.proofNote,
          ),
        },
      );
      // Refresh every quarterly-sheet query for this employee.
      ref.invalidate(quarterlySheetProvider);
    } catch (e) {
      // A 409 means our copy of the review is stale — the month locked while
      // this sheet was open. Re-read it so the edit affordances disappear
      // instead of inviting the same doomed save again.
      if (e is ApiError && e.statusCode == 409) {
        ref.invalidate(quarterlySheetProvider);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_saveErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// User-facing text for a failed save.
  ///
  /// `'$e'` on an [ApiError] renders its `toString()` — the debug form
  /// (`ApiError(ApiErrorType.validation, code=RES_002, status=409, msg="…")`),
  /// which is what used to reach the SnackBar. [ApiError.combinedMessage] is
  /// the sanitised text the backend actually wrote for the user, so a lock
  /// reads as "Review is completed; scores are locked." RES_002 is a generic
  /// conflict code (it also covers "Template already exists"), so it is
  /// deliberately not mapped to a fixed string here.
  String _saveErrorText(Object e) =>
      e is ApiError ? e.combinedMessage : 'Could not save. Please try again.';

  /// Months in this quarter whose self-rating this viewer may SUBMIT.
  ///
  /// Conditions:
  ///   * it is their own sheet ([_canEditSelf]);
  ///   * at least one KRA carries a self score. Submitting an untouched month
  ///     would hand the manager an empty sheet and email them about it;
  ///   * it has not already been submitted — a stage record for Self-Rating is
  ///     what proves that, so the button disappears once used.
  ///
  /// Note what is NOT required: the cursor still being on `SELF_RATING`. Gating
  /// on that made the button impossible to reach against a backend that still
  /// auto-advances the cursor when a score is saved — before rating there is
  /// nothing to submit, and after rating the cursor had already moved, so the
  /// window never opened. A stale server is now handled where it belongs, on the
  /// response (see [_submitSelfRating]), rather than by hiding the action.
  List<MonthlyReview> _submittableReviews(
    List<MonthlyReview?> reviews,
    ReviewScope? scope,
  ) =>
      [
        for (final r in reviews.whereType<MonthlyReview>())
          if (_canEditSelf(r, scope) &&
              _hasSelfScore(r) &&
              r.recordFor(ReviewStage.selfRating) == null)
            r,
      ];

  /// True when any KRA has a self score.
  ///
  /// Tests for PRESENCE, not a positive total: an employee who honestly rates
  /// everything 0 has still rated, and a weighted-total test would have silently
  /// refused to let them submit.
  bool _hasSelfScore(MonthlyReview r) =>
      r.rows.any((row) => row.scoreFor(ReviewStage.selfRating)?.value != null);

  /// The submit action, or null when there is nothing to submit — which keeps the
  /// bar off other people's sheets, off months already submitted, and off months
  /// with nothing rated yet.
  Future<void> Function()? _submitAction(
    List<MonthlyReview?> reviews,
    ReviewScope? scope,
  ) {
    if (scope == null) return null;
    final targets = _submittableReviews(reviews, scope);
    if (targets.isEmpty) return null;
    return () => _submitSelfRating(targets, scope);
  }

  /// Submits the self-rating for [targets] and confirms it.
  ///
  /// The backend advances each review to the reporting manager and emails them
  /// (CC HR) once the transaction commits — so this is the point of no return for
  /// the employee, hence the confirmation before and the explicit
  /// acknowledgement after.
  Future<void> _submitSelfRating(
    List<MonthlyReview> targets,
    ReviewScope scope,
  ) async {
    final months = targets.map((r) => r.period.label).join(', ');
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.selfSubmitConfirmTitle,
      message: '${AppStrings.selfSubmitConfirmMessage}\n\n$months',
      confirmLabel: AppStrings.selfSubmitConfirmAction,
      cancelLabel: AppStrings.commonCancel,
      icon: Icons.task_alt_rounded,
      accentColor: AppColors.primaryPurple,
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(monthlyReviewRepositoryProvider);
      for (final review in targets) {
        await repo.submitStage(
          review.id,
          ReviewStage.selfRating,
          actorId: scope.userId,
          actorName: scope.userName,
        );
      }
      ref.invalidate(quarterlySheetProvider);
      // The home card and the manager's list both read the summary, so drop the
      // cached lists as well or the submitted state won't show there.
      ref.invalidate(monthlyReviewListProvider);
      if (mounted) await _showSubmittedDialog();
    } catch (e) {
      if (mounted) {
        // A 409 here means the server has moved this review past Self-Rating —
        // either someone else advanced it, or the deployment still auto-advances
        // the cursor when a score is saved. Say that, rather than showing a raw
        // "Review is at REPORTING_MANAGER_RATING, not SELF_RATING".
        final conflict = e is ApiError && e.statusCode == 409;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(conflict
                ? AppStrings.selfSubmitAlreadyMoved
                : '${AppStrings.selfSubmitFailed} '
                    '${e is ApiError ? e.message : e}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The "submitted successfully" acknowledgement. A dialog rather than a
  /// snackbar: this is the end of the employee's task and it tells them the
  /// manager has been notified, which is worth an explicit dismissal.
  Future<void> _showSubmittedDialog() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          icon: const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 44),
          title: const Text(
            AppStrings.selfSubmitDoneTitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          content: Text(
            AppStrings.selfSubmitDoneMessage,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            Center(
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple),
                child: const Text(AppStrings.commonClose),
              ),
            ),
          ],
        ),
      );

  /// Months in this quarter whose self-rating this viewer may hand back: the
  /// pipeline is sitting on the manager's rating (so `submit-stage` will accept
  /// it — the backend rejects a stage that isn't the current one) and the viewer
  /// is that review's reporting manager.
  List<MonthlyReview> _returnableReviews(
    List<MonthlyReview?> reviews,
    ReviewScope? scope,
  ) =>
      [
        for (final r in reviews.whereType<MonthlyReview>())
          if (r.currentStage == ReviewStage.reportingManagerRating &&
              _canEditManager(r, scope))
            r,
      ];

  /// The rework action, or null when this viewer has nothing to hand back —
  /// which is what keeps the bar off the sheet for employees, other people's
  /// managers, and months not sitting at the manager's stage.
  Future<void> Function()? _reworkAction(
    List<MonthlyReview?> reviews,
    ReviewScope? scope,
  ) {
    if (scope == null) return null;
    final targets = _returnableReviews(reviews, scope);
    if (targets.isEmpty) return null;
    return () => _sendBackForRework(targets, scope);
  }

  /// Sends the self-rating back to the employee for revision, with a reason.
  ///
  /// Applies to every returnable month in the quarter, so one explanation covers
  /// the sheet the manager is actually looking at rather than making them repeat
  /// it per month. Scores are left alone — the employee revises what is there.
  Future<void> _sendBackForRework(
    List<MonthlyReview> targets,
    ReviewScope scope,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReworkReasonDialog(),
    );
    if (reason == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(monthlyReviewRepositoryProvider);
      for (final review in targets) {
        await repo.submitStage(
          review.id,
          ReviewStage.reportingManagerRating,
          approved: false,
          comment: reason,
          actorId: scope.userId,
          actorName: scope.userName,
        );
      }
      ref.invalidate(quarterlySheetProvider);
      // The manager's list badges this from the summary flag, so drop it too.
      ref.invalidate(monthlyReviewListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.sheetReworkDone)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not send back: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Commits the Management column across the whole quarter in one action.
  ///
  /// For every KRA in each month, the management score is written as: the
  /// management override the reviewer set, else the Review-cycle score copied in
  /// (the value the cell was pre-filled with). Rows with no Review score yet are
  /// skipped — there's nothing to lock. Persisting these makes them the official
  /// management scores, so the incentive is computed from the management review;
  /// KRAs management didn't change keep the stage-2 Review score they inherited.
  Future<void> _lockManagementReview(List<MonthlyReview?> reviews) async {
    // How many KRA/months carry a Review or management score to commit.
    var pending = 0;
    for (final review in reviews) {
      if (review == null) continue;
      for (final row in review.rows) {
        final hasMgmt =
            row.scoreFor(ReviewStage.managementReview)?.value != null;
        final hasReview = review.reviewPctForRow(row) != null;
        if (hasReview || hasMgmt) pending++;
      }
    }
    if (pending == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nothing to lock yet — the Review scores aren’t in '
                'for these KRAs.')));
      }
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Lock the management review?'),
        content: const Text(
            'This saves a Management score for every KRA this quarter — the '
            'Review score for the ones you didn’t change, and your edits for '
            'the rest — and the incentive is calculated from them. You can '
            'still edit and lock again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryPurple),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save & Lock'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(monthlyReviewRepositoryProvider);
      for (final review in reviews) {
        if (review == null) continue;
        final rowScores = <String, RowScore>{};
        for (final row in review.rows) {
          final existing = row.scoreFor(ReviewStage.managementReview);
          double? value;
          if (existing?.value != null) {
            value = existing!.value; // keep management's own edit
          } else {
            final rp = review.reviewPctForRow(row);
            if (rp != null && row.maxScore > 0) {
              value = rp / 100 * row.maxScore; // copy the Review score in
            }
          }
          if (value != null) {
            rowScores[row.id] = RowScore(
              value: value,
              remark: existing?.remark,
              proofNote: existing?.proofNote,
            );
          }
        }
        if (rowScores.isNotEmpty) {
          await repo.saveStageScores(
            review.id,
            ReviewStage.managementReview,
            rowScores: rowScores,
          );
        }
        // Lock the review so its management scores are fixed and the incentive
        // is settled to them until it's explicitly reopened.
        await repo.lockManagement(review.id);
      }
      ref.invalidate(quarterlySheetProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Management review saved and locked — incentive settled to it.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Reopens a locked management review across the quarter so its scores can be
  /// revised, then re-locked.
  Future<void> _reopenManagement(List<MonthlyReview?> reviews) async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(monthlyReviewRepositoryProvider);
      for (final review in reviews) {
        if (review == null || !review.isManagementLocked) continue;
        await repo.unlockManagement(review.id);
      }
      ref.invalidate(quarterlySheetProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Management review reopened — you can edit again.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not reopen: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Fetches a row's stored proof attachment and shows it.
  ///
  /// Bytes are pulled on demand (never inlined in the sheet payload). The
  /// backend gates this with the same rule as reading the review, so the
  /// employee, their reporting manager — whatever that manager's role — and
  /// management can all open it.
  Future<void> _openProofFile(
      MonthlyReview review, String rowId, ReviewStage stage) async {
    setState(() => _saving = true);
    try {
      final file = await ref
          .read(monthlyReviewRepositoryProvider)
          .fetchProofFile(review.id, rowId, stage);
      if (!mounted) return;
      if (file == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No proof file stored for this KRA.')),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => _ProofFileViewer(file: file),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open proof: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The per-KRA, per-MONTH, per-STAGE "Reason & Proof" entry. Each month
  /// captures a reason (max 300 chars) + one proof attachment PER contributor:
  /// the EMPLOYEE files evidence on their SELF rating, and each Review-cycle
  /// reviewer (Reporting Manager / HR / Accounts) files their own on their
  /// rating stage. Whoever owns [stage] can edit it; everyone else can view +
  /// download it. Reason + attachment persist on that (row, stage) score.
  Future<void> _openJustification({
    required MonthlyReview review,
    required String rowId,
    required ReviewStage stage,
    required String kraName,
    required String monthLabel,
    required bool canEdit,
  }) async {
    final current = _currentScore(review, rowId, stage);
    final key = '${review.id}|$rowId|${stage.name}';
    // Seed from the STORED attachment (bytes null = "already on the server,
    // untouched"). Without this the editor would look empty to someone who has
    // an attachment, and saving a reason would then read as "removed" and wipe
    // it. A fresh local pick wins, since it hasn't been uploaded yet.
    final stored = current?.proofFileName;
    final initialFile = _proofFiles[key] ??
        (stored != null && stored.isNotEmpty
            ? (name: stored, bytes: null)
            : null);

    if (!canEdit) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => _JustificationView(
          kraName: kraName,
          monthLabel: monthLabel,
          reason: current?.remark ?? '',
          // The STORED name — this is the manager/management view, and they
          // never picked the file, so their own local map is (correctly) empty.
          // Reading the server's value is what makes the employee's evidence
          // actually visible to the person rating them.
          fileName: current?.proofFileName ?? _proofFiles[key]?.name,
          onOpenFile: (current?.proofFileName?.isNotEmpty ?? false)
              ? () => _openProofFile(review, rowId, stage)
              : null,
        ),
      );
      return;
    }

    final result = await showDialog<_JustificationResult>(
      context: context,
      builder: (ctx) => _JustificationDialog(
        kraName: kraName,
        monthLabel: monthLabel,
        initialReason: current?.remark ?? '',
        initialFile: initialFile,
      ),
    );
    if (result == null) return;

    setState(() => _saving = true);
    try {
      // Attachment tri-state — the dialog hands back the CURRENT selection:
      //   * bytes present → the user picked a new file → upload (replace).
      //   * record but no bytes → the stored file, untouched → send nothing so
      //     the server PRESERVES it (never re-upload it just to save a reason).
      //   * null → the user removed it → clear it server-side.
      final picked = result.file;
      final upload = picked?.bytes != null
          ? ProofFileUpload(
              name: picked!.name,
              mime: _mimeFor(picked.name),
              base64Data: base64Encode(picked.bytes!),
            )
          : null;
      // Preserve this stage's existing score — the reason rides alongside it.
      await ref.read(monthlyReviewRepositoryProvider).saveStageScores(
        review.id,
        stage,
        rowScores: {
          rowId: RowScore(
            value: current?.value,
            remark: result.reason.trim().isEmpty ? null : result.reason.trim(),
            proofNote: null,
            proofFile: upload,
            clearProofFile: picked == null,
          ),
        },
      );
      // Local copy is just an optimistic echo; the server's proofFileName is
      // the source of truth from the next fetch on (and is what OTHER viewers —
      // the reporting manager, management — actually read).
      if (picked != null) {
        _proofFiles[key] = picked;
      } else {
        _proofFiles.remove(key);
      }
      ref.invalidate(quarterlySheetProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(currentReviewScopeProvider);
    final employeeId = widget.employeeId ?? scope?.userId;
    _anchor ??= ref.read(selectedPeriodProvider) ??
        ref.read(availablePeriodsProvider).first;

    if (employeeId == null) {
      return const Scaffold(
        body: Center(child: Text('Not signed in.')),
      );
    }

    final sheetAsync = ref.watch(
        quarterlySheetProvider((employeeId: employeeId, anchor: _anchor!)));
    // Per-KRA reviewer assignment resolved from the template — fills in the
    // reviewer on any row that arrived without it, so the "assigned reviewer
    // only" rule holds even for rows the backend hasn't snapshotted it onto.
    final reviewerMap =
        ref.watch(kraReviewerMapProvider(employeeId)).valueOrNull ??
            (
              byName: const <String, KraReviewer>{},
              byOrder: const <KraReviewer?>[]
            );

    return Scaffold(
      backgroundColor: AppColors.background,
      // Left "☰" workspace menu — shows for manager/HR viewing their own sheet;
      // null (no menu) for a plain employee, who has only My KRA.
      drawer: workspaceDrawerFor(ref),
      appBar: AppBar(
        // Back wins over the drawer "☰" when this sheet was pushed (e.g. an
        // admin opening a colleague's sheet) — otherwise there's no way back.
        leading: adaptiveLeading(context),
        title: const Text(AppStrings.quarterlySheetTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: sheetAsync.when(
        loading: () => const _Skeleton(),
        error: (e, _) => _SheetError(
          message: e is ApiError
              ? e.combinedMessage
              : 'Something went wrong. Please try again.',
          onRetry: () => ref.invalidate(quarterlySheetProvider(
              (employeeId: employeeId, anchor: _anchor!))),
        ),
        data: (data) {
          final mappedReviews = [
            for (final r in data.reviews) _applyReviewerMap(r, reviewerMap),
          ];
          final canManage = _hasManagementRole(scope);
          return _Sheet(
            months: data.months,
            reviews: mappedReviews,
            scope: scope,
            onPrevQuarter: () => setState(() => _anchor =
                quarterMonthsFor(_anchor!)
                    .first
                    .let((m) => _shiftQuarter(m, -1))),
            onNextQuarter: () => setState(() => _anchor =
                quarterMonthsFor(_anchor!)
                    .first
                    .let((m) => _shiftQuarter(m, 1))),
            pct: _pct,
            canEditSelf: (r) => _canEditSelf(r, scope),
            canEditManager: (r) => _canEditManager(r, scope),
            canEditHr: (r) => _canEditHr(r, scope),
            canEditFinance: (r) => _canEditFinance(r, scope),
            canEditManagement: (r) => _canEditManagement(r, scope),
            onEdit: _editCell,
            onJustify: _openJustification,
            // Server value first: a viewer never picked the file, so only the
            // stored name can tell them evidence exists. The local pick is just
            // an optimistic echo for whoever uploaded it. Keyed by stage so the
            // employee's and each reviewer's attachments are tracked separately.
            fileNameFor: (review, rowId, stage) =>
                _currentScore(review, rowId, stage)?.proofFileName ??
                _proofFiles['${review.id}|$rowId|${stage.name}']?.name,
            // Management commits the whole column at once (copy Review → Mgmt
            // for anything they didn't change) and locks the incentive to it,
            // or reopens a locked review to revise it.
            onLockManagement:
                canManage ? () => _lockManagementReview(mappedReviews) : null,
            onReopenManagement:
                canManage ? () => _reopenManagement(mappedReviews) : null,
            // The reporting manager can hand a self-rating back when it looks
            // wrong. Null unless they actually have a month to return.
            onSendBackForRework: _reworkAction(mappedReviews, scope),
            // The employee finalises their own rating; null for everyone else.
            onSubmitSelfRating: _submitAction(mappedReviews, scope),
          );
        },
      ),
    );
  }

  ReviewPeriod _shiftQuarter(ReviewPeriod quarterStart, int delta) {
    var m = quarterStart.month + delta * 3;
    var y = quarterStart.year;
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    return ReviewPeriod(y, m);
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Builds the quarterly-sheet body from plain data (no providers/auth) so
/// widget tests can exercise its layout in isolation — e.g. assert the grid
/// renders a full "100%" editable cell without a RenderFlex overflow.
@visibleForTesting
Widget quarterlyKraSheetBodyForTest({
  required List<ReviewPeriod> months,
  required List<MonthlyReview?> reviews,
  bool editableSelf = true,
  bool editableManager = false,
  bool editableHr = false,
  bool editableFinance = false,
  bool editableManagement = false,
  Future<void> Function()? onLockManagement,
  Future<void> Function()? onReopenManagement,
  Future<void> Function()? onSendBackForRework,
  Future<void> Function()? onSubmitSelfRating,
}) {
  double? pct(MonthlyReview? r, String rowId, ReviewStage stage) {
    if (r == null) return null;
    for (final row in r.rows) {
      if (row.id != rowId) continue;
      final s = row.scoreFor(stage);
      if (s?.value != null && row.maxScore > 0) {
        return (s!.value! / row.maxScore) * 100;
      }
      return null;
    }
    return null;
  }

  return _Sheet(
    months: months,
    reviews: reviews,
    scope: null,
    onPrevQuarter: () {},
    onNextQuarter: () {},
    pct: pct,
    // The bool flags say what ROLE the harness is signed in as; a completed
    // month still refuses the edit, exactly as the real gates do.
    canEditSelf: (r) => editableSelf && !r.isComplete,
    canEditManager: (r) => editableManager && !r.isComplete,
    canEditHr: (r) => editableHr && !r.isComplete,
    canEditFinance: (r) => editableFinance && !r.isComplete,
    canEditManagement: (r) => editableManagement && !r.isComplete,
    onEdit: ({
      required review,
      required rowId,
      required maxScore,
      required stage,
      required currentPct,
      required kraName,
      required monthLabel,
    }) async {},
    onJustify: ({
      required review,
      required rowId,
      required stage,
      required kraName,
      required monthLabel,
      required canEdit,
    }) async {},
    fileNameFor: (_, __, ___) => null,
    onLockManagement: onLockManagement,
    onReopenManagement: onReopenManagement,
    onSendBackForRework: onSendBackForRework,
    onSubmitSelfRating: onSubmitSelfRating,
  );
}

class _Sheet extends StatelessWidget {
  final List<ReviewPeriod> months;
  final List<MonthlyReview?> reviews;
  final ReviewScope? scope;
  final VoidCallback onPrevQuarter;
  final VoidCallback onNextQuarter;
  final double? Function(MonthlyReview?, String, ReviewStage) pct;
  final bool Function(MonthlyReview) canEditSelf;
  final bool Function(MonthlyReview) canEditManager;
  // Role-based (not relationship): the HR / Accounts Review raters and the
  // Management override. A KRA's Review cell is editable only by its assigned
  // reviewer — RM via [canEditManager] (relationship), HR via [canEditHr],
  // Accounts via [canEditFinance].
  //
  // These take the month's review rather than a bare bool so they can refuse a
  // completed month. A role alone can't answer "is this editable?" — the
  // quarter's three months lock independently.
  final bool Function(MonthlyReview) canEditHr;
  final bool Function(MonthlyReview) canEditFinance;
  final bool Function(MonthlyReview) canEditManagement;
  final Future<void> Function({
    required MonthlyReview review,
    required String rowId,
    required double maxScore,
    required ReviewStage stage,
    required double? currentPct,
    required String kraName,
    required String monthLabel,
  }) onEdit;
  final Future<void> Function({
    required MonthlyReview review,
    required String rowId,
    required ReviewStage stage,
    required String kraName,
    required String monthLabel,
    required bool canEdit,
  }) onJustify;
  final String? Function(MonthlyReview, String, ReviewStage) fileNameFor;

  // Management-only: persist the whole Management column in one go — copying the
  // Review score into every KRA management hasn't overridden, keeping the ones
  // they have — so the incentive is locked to the management review. Null for
  // non-management viewers (the "Save & Lock" bar is hidden for them).
  final Future<void> Function()? onLockManagement;

  // Management-only: reopen a locked management review so its scores can be
  // revised, then re-locked. Null for non-management viewers.
  final Future<void> Function()? onReopenManagement;

  /// Non-null when the viewer is the reporting manager of at least one month in
  /// this quarter whose self-rating they may send back for revision.
  final Future<void> Function()? onSendBackForRework;

  /// Non-null when the viewer owns at least one month in this quarter that is
  /// still at Self-Rating and has something rated to submit.
  final Future<void> Function()? onSubmitSelfRating;

  const _Sheet({
    required this.months,
    required this.reviews,
    required this.scope,
    required this.onPrevQuarter,
    required this.onNextQuarter,
    required this.pct,
    required this.canEditSelf,
    required this.canEditManager,
    required this.canEditHr,
    required this.canEditFinance,
    required this.canEditManagement,
    required this.onEdit,
    required this.onJustify,
    required this.fileNameFor,
    this.onLockManagement,
    this.onReopenManagement,
    this.onSendBackForRework,
    this.onSubmitSelfRating,
  });

  MonthlyReview? get _any =>
      reviews.firstWhere((r) => r != null, orElse: () => null);

  @override
  Widget build(BuildContext context) {
    final any = _any;
    if (any == null) {
      // A review row only exists once HR has generated the cycle's monthly
      // reviews. Employees added mid-cycle land here until that happens, so
      // explain it rather than dead-ending on a bare "no review" line.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_note_outlined,
                  size: 44, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(
                'No review to rate yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This quarter’s review hasn’t been set up for these '
                'KRAs yet. It will appear here once HR generates it — '
                'please check back or contact HR.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Canonical KRA rows (same template across months) from the first review.
    final rows = [...any.rows]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    // Weighted monthly totals per stage (0–100) and the quarter average.
    double monthTotal(int i, ReviewStage stage) =>
        reviews[i]?.weightedScorePct(stage) ?? 0;
    double qAvg(ReviewStage stage) =>
        (monthTotal(0, stage) + monthTotal(1, stage) + monthTotal(2, stage)) /
        3;

    // Editability is per MONTH, not per sheet: the quarter's three reviews
    // advance and lock independently, so a banner derived from one of them
    // ([any]) would promise edit rights the other two months refuse. Ask every
    // month present and claim only what at least one of them allows.
    final present = reviews.whereType<MonthlyReview>().toList();
    bool inAnyMonth(bool Function(MonthlyReview) can) => present.any(can);

    final canSelf = inAnyMonth(canEditSelf);
    final canMgr = inAnyMonth(canEditManager);
    final canHr = inAnyMonth(canEditHr);
    final canFin = inAnyMonth(canEditFinance);
    final canMgmt = inAnyMonth(canEditManagement);
    final canEditAny = canSelf || canMgr || canHr || canFin || canMgmt;

    // "Locked" and "not yours to edit" are different answers and deserve
    // different words — a finished quarter is nobody's to edit.
    final allComplete =
        present.isNotEmpty && present.every((r) => r.isComplete);
    final scopeLabel = canSelf
        ? 'You can edit the Self ratings on this sheet.'
        : canMgr
            ? 'You can rate the KRAs assigned to you as Reporting Manager — '
                'tap a Review cell.'
            : canHr
                ? 'You can rate the KRAs assigned to HR — tap a Review cell.'
                : canFin
                    ? 'You can rate the KRAs assigned to Accounts — '
                        'tap a Review cell.'
                    : canMgmt
                        ? 'You can enter the Management rating for each KRA.'
                        : allComplete
                            ? 'This quarter is completed — scores are locked.'
                            : 'View only — you cannot edit this sheet.';

    // Payout follows the FINAL score (management override → Review average →
    // self), quarter-averaged across the three months.
    double qFinalOf() {
      double sum = 0;
      for (var i = 0; i < 3; i++) {
        sum += reviews[i]?.finalScorePct ?? 0;
      }
      return sum / 3;
    }

    final qFinal = qFinalOf();
    final qSelf = qAvg(ReviewStage.selfRating);
    final eligibleMonthly = any.eligibleAmount;
    final quarterEligible = eligibleMonthly * 3;
    final payout = quarterEligible * qFinal / 100;

    // Centre the sheet at a max width matching the grid so the header, table
    // and payout card stay aligned and don't stretch edge-to-edge on a desktop.
    // 1320 comfortably fits the grid (~1282), so this never forces new
    // horizontal scrolling; on a phone it's simply full width.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _HeaderCard(
              review: any,
              months: months,
              onPrev: onPrevQuarter,
              onNext: onNextQuarter,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(
                      canEditAny
                          ? Icons.edit_rounded
                          : Icons.visibility_rounded,
                      size: 14,
                      color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(scopeLabel,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            // Any month whose self-rating the manager handed back. Shown to
            // everyone who can see the sheet, not just the employee: the reason
            // is the audit trail for why the pipeline went backwards.
            for (final r in reviews.whereType<MonthlyReview>())
              if (r.selfRatingReturned)
                _ReworkNotice(
                  monthLabel: r.period.label,
                  record:
                      r.returnedRecordFor(ReviewStage.reportingManagerRating)!,
                ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _ReviewerLegend(),
            ),
            // Frame the table so its edge columns don't merge with the screen
            // edge — a bordered, rounded card (matching the header/payout cards)
            // with a little internal padding, and a horizontal margin that keeps
            // it inset from the window. The scroll is clipped to the rounded
            // corners so content slides cleanly under the border.
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.dividerStrong),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _Grid(
                  rows: rows,
                  months: months,
                  reviews: reviews,
                  pct: pct,
                  canEditSelf: canEditSelf,
                  canEditManager: canEditManager,
                  canEditHr: canEditHr,
                  canEditFinance: canEditFinance,
                  canEditManagement: canEditManagement,
                  onEdit: onEdit,
                  onJustify: onJustify,
                  fileNameFor: fileNameFor,
                  monthTotal: monthTotal,
                  qAvg: qAvg,
                ),
              ),
            ),
            // Sits directly under the table, at the END of the ratings — the
            // employee scrolls through every KRA and then submits.
            if (onSubmitSelfRating != null) ...[
              const SizedBox(height: 14),
              _SubmitSelfRatingBar(onSubmit: onSubmitSelfRating!),
            ],
            if (onSendBackForRework != null) ...[
              const SizedBox(height: 14),
              _ReworkBar(onSendBack: onSendBackForRework!),
            ],
            if (onLockManagement != null) ...[
              const SizedBox(height: 14),
              _LockManagementBar(
                // Locked once every month present this quarter is locked.
                locked: reviews.whereType<MonthlyReview>().isNotEmpty &&
                    reviews
                        .whereType<MonthlyReview>()
                        .every((r) => r.isManagementLocked),
                onSave: onLockManagement!,
                onReopen: onReopenManagement,
              ),
            ],
            const SizedBox(height: 16),
            _PayoutCard(
              qSelf: qSelf,
              qFinal: qFinal,
              eligibleMonthly: eligibleMonthly,
              quarterEligible: quarterEligible,
              payout: payout,
            ),
          ],
        ),
      ),
    );
  }
}

/// Management-only action bar. While the review is OPEN it offers "Save & Lock"
/// — one tap copies the Review score into every KRA management hasn't overridden
/// and persists the whole Management column, so the incentive is locked to the
/// management review (unchanged rows keep the stage-2 Review score they
/// inherited). Once LOCKED it reads as locked and offers "Reopen" to revise.
class _LockManagementBar extends StatefulWidget {
  final bool locked;
  final Future<void> Function() onSave;
  final Future<void> Function()? onReopen;
  const _LockManagementBar({
    required this.locked,
    required this.onSave,
    required this.onReopen,
  });

  @override
  State<_LockManagementBar> createState() => _LockManagementBarState();
}

class _LockManagementBarState extends State<_LockManagementBar> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked;
    final accent = locked ? AppColors.success : AppColors.primaryPurple;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(locked ? Icons.lock_rounded : Icons.verified_rounded,
                color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(locked ? 'Management review locked' : 'Management review',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  locked
                      ? 'The incentive is locked to these management scores. '
                          'Reopen to change them.'
                      : 'Saves the Management column — the Review score for '
                          'every KRA you haven’t changed, plus your edits — and '
                          'locks the incentive to it.',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (locked)
            OutlinedButton.icon(
              onPressed: (_busy || widget.onReopen == null)
                  ? null
                  : () => _run(widget.onReopen!),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('Reopen'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryPurple,
                side: BorderSide(
                    color: AppColors.primaryPurple.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(widget.onSave),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.lock_rounded, size: 18),
              label: const Text('Save & Lock'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final MonthlyReview review;
  final List<ReviewPeriod> months;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _HeaderCard({
    required this.review,
    required this.months,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [AppColors.primaryPurple, AppColors.primaryPurpleLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            review.employeeName,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (review.employeeCode.isNotEmpty) review.employeeCode,
              if (review.grade != null) 'Grade ${review.grade}',
              if (review.managerName != null) 'Mgr: ${review.managerName}',
            ].join('  ·  '),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          // Fiscal quarter this sheet covers — auto-derived from the months on
          // view (Q1 = Apr–Jun, Q2 = Jul–Sep, Q3 = Oct–Dec, Q4 = Jan–Mar), so
          // it updates as you page between quarters and flags the live one.
          _quarterBadge(),
          const SizedBox(height: 12),
          Row(
            children: [
              _navBtn(Icons.chevron_left_rounded, onPrev),
              const SizedBox(width: 8),
              Text(
                '${months.first.shortLabel} – ${months.last.shortLabel}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
              const SizedBox(width: 8),
              _navBtn(Icons.chevron_right_rounded, onNext),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quarterBadge() {
    final anchor = months.first;
    final now = ReviewPeriod.fromDate(DateTime.now());
    final isCurrent = now.fiscalQuarter == anchor.fiscalQuarter &&
        now.fiscalYearStartYear == anchor.fiscalYearStartYear;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_month_rounded,
                size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text('Q${anchor.fiscalQuarter}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14)),
            const SizedBox(width: 6),
            Text(anchor.fiscalYearLabel,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ]),
        ),
        if (isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
              SizedBox(width: 4),
              Text('Current quarter',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11)),
            ]),
          ),
      ],
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) => Material(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );
}

/// A compact key explaining the per-KRA reviewer colours and the pending
/// status, so the single-reviewer model reads clearly at the top of the sheet.
class _ReviewerLegend extends StatelessWidget {
  const _ReviewerLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('One reviewer per KRA:',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted)),
        for (final r in KraReviewer.values) _dot(r),
        const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.schedule_rounded, size: 11, color: AppColors.warning),
          SizedBox(width: 3),
          Text('review pending',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning)),
        ]),
      ],
    );
  }

  Widget _dot(KraReviewer r) {
    final color = _reviewerColor(r);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(r.shortLabel,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

class _Grid extends StatefulWidget {
  final List<dynamic> rows; // MonthlyKraRow
  final List<ReviewPeriod> months;
  final List<MonthlyReview?> reviews;
  final double? Function(MonthlyReview?, String, ReviewStage) pct;
  final bool Function(MonthlyReview) canEditSelf;
  final bool Function(MonthlyReview) canEditManager;
  final bool Function(MonthlyReview) canEditHr;
  final bool Function(MonthlyReview) canEditFinance;
  final bool Function(MonthlyReview) canEditManagement;
  final Future<void> Function({
    required MonthlyReview review,
    required String rowId,
    required double maxScore,
    required ReviewStage stage,
    required double? currentPct,
    required String kraName,
    required String monthLabel,
  }) onEdit;
  // The Reason & Proof entry is per KRA, per month AND per stage — the employee
  // files evidence on self, each reviewer on their own rating stage.
  final Future<void> Function({
    required MonthlyReview review,
    required String rowId,
    required ReviewStage stage,
    required String kraName,
    required String monthLabel,
    required bool canEdit,
  }) onJustify;
  final String? Function(MonthlyReview, String, ReviewStage) fileNameFor;
  final double Function(int, ReviewStage) monthTotal;
  final double Function(ReviewStage) qAvg;

  const _Grid({
    required this.rows,
    required this.months,
    required this.reviews,
    required this.pct,
    required this.canEditSelf,
    required this.canEditManager,
    required this.canEditHr,
    required this.canEditFinance,
    required this.canEditManagement,
    required this.onEdit,
    required this.onJustify,
    required this.fileNameFor,
    required this.monthTotal,
    required this.qAvg,
  });

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> {
  // Which KRAs have their Reason & Proof line item expanded (by rowId).
  final Set<String> _expanded = {};

  // Fixed column widths so every row — and the full-width expandable line
  // item beneath it — stays aligned inside the horizontal scroll. Month
  // columns are sized for the widest editable value ("100%" + edit icon).
  static const double _wWt = 44,
      _wKra = 170,
      _wTgt = 112,
      _wTrk = 158,
      _wMon = 70,
      _wQtr = 56;
  // Per month: Self | Review | Mgmt (3 cols). Quarter: Self | Review | Final.
  double get _totalWidth =>
      _wWt + _wKra + _wTgt + _wTrk + _wMon * 9 + _wQtr * 3;

  String _fmt(double? p) => p == null ? '—' : '${p.round()}%';

  // Locate row [rowId] within a specific month's review — each month carries
  // its own scores AND the row's reviewer assignment.
  MonthlyKraRow? _rowIn(MonthlyReview? r, String rowId) {
    if (r == null) return null;
    for (final row in r.rows) {
      if (row.id == rowId) return row;
    }
    return null;
  }

  // Review-cycle score for ONE KRA/month, straight from the model so every
  // surface agrees: the ASSIGNED reviewer's rating (null until they score),
  // averaging only for legacy unassigned rows. See MonthlyReview.reviewPctForRow.
  double? _reviewPct(MonthlyReview? r, String rowId) {
    final row = _rowIn(r, rowId);
    if (row == null) return null;
    return r!.reviewPctForRow(row);
  }

  // The final score for ONE KRA/month (management override → Review → self),
  // per row, straight from the model so the Qtr Final column, totals and payout
  // all agree. See MonthlyReview.finalPctForRow.
  double? _rowFinalPct(MonthlyReview? r, String rowId) {
    final row = _rowIn(r, rowId);
    if (row == null) return null;
    return r!.finalPctForRow(row);
  }

  // The stages that carry a Reason & Proof entry for a KRA row: the employee's
  // SELF evidence, plus the assigned reviewer's (RM/HR/Accounts) if the KRA is
  // assigned. Legacy unassigned rows keep just the employee slot.
  List<ReviewStage> _evidenceStages(MonthlyKraRow? row) {
    final stages = <ReviewStage>[ReviewStage.selfRating];
    final rs = row?.reviewStage;
    if (rs != null) stages.add(rs);
    return stages;
  }

  // A KRA is "justified" if ANY month has a reason or attachment on the employee
  // entry OR its assigned reviewer's entry.
  bool _anyJustified(String rowId) {
    for (final r in widget.reviews) {
      if (r == null) continue;
      final row = _rowIn(r, rowId);
      for (final stage in _evidenceStages(row)) {
        final s = row?.scoreFor(stage);
        if (s?.remark?.trim().isNotEmpty ?? false) return true;
        if (widget.fileNameFor(r, rowId, stage) != null) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _totalWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerRow(),
          for (final row in widget.rows) ..._kraBlock(row),
          _totalsRow(),
        ],
      ),
    );
  }

  Widget _cell(double w, Widget child,
      {Alignment align = Alignment.centerRight}) {
    return SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Align(alignment: align, child: child),
      ),
    );
  }

  Widget _headerRow() {
    final h = TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: AppColors.textMuted,
        height: 1.15);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(children: [
        _cell(_wWt, Text('Wt', style: h), align: Alignment.centerLeft),
        _cell(_wKra, Text('KRA', style: h), align: Alignment.centerLeft),
        _cell(_wTgt, Text('Target', style: h), align: Alignment.centerLeft),
        _cell(_wTrk, Text('Tracking\nmethod', style: h),
            align: Alignment.centerLeft),
        for (final m in widget.months) ...[
          _cell(
              _wMon,
              Text('${m.shortLabel}\nSelf',
                  style: h, textAlign: TextAlign.right)),
          _cell(
              _wMon,
              Text('${m.shortLabel}\nReview',
                  style: h, textAlign: TextAlign.right)),
          _cell(
              _wMon,
              Text('${m.shortLabel}\nMgmt',
                  style: h, textAlign: TextAlign.right)),
        ],
        _cell(_wQtr, Text('Qtr\nSelf', style: h, textAlign: TextAlign.right)),
        _cell(_wQtr, Text('Qtr\nReview', style: h, textAlign: TextAlign.right)),
        _cell(_wQtr, Text('Qtr\nFinal', style: h, textAlign: TextAlign.right)),
      ]),
    );
  }

  List<Widget> _kraBlock(dynamic row) {
    final rowId = row.id as String;
    return [
      Container(
        decoration: BoxDecoration(
          border: Border(
              bottom:
                  BorderSide(color: AppColors.divider.withValues(alpha: 0.5))),
        ),
        child: _mainRow(row),
      ),
      if (_expanded.contains(rowId))
        Container(
          width: _totalWidth,
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.035),
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: _lineItem(row),
        ),
    ];
  }

  Widget _mainRow(dynamic row) {
    final rowId = row.id as String;
    final maxScore = (row.maxScore as num).toDouble();
    final name = row.name as String;
    // Quarter average of a per-row extractor across the three months (missing
    // months count as 0, matching the totals row).
    double qAvgRow(double? Function(MonthlyReview?) f) {
      double sum = 0;
      for (var i = 0; i < 3; i++) {
        sum += f(widget.reviews[i]) ?? 0;
      }
      return sum / 3;
    }

    return Row(children: [
      _cell(
          _wWt,
          Text('${(row.weightagePercent as num).round()}%',
              style: const TextStyle(fontSize: 12)),
          align: Alignment.centerLeft),
      _cell(_wKra, _kraNameBlock(row), align: Alignment.centerLeft),
      _cell(_wTgt, _targetCell(row), align: Alignment.centerLeft),
      _cell(_wTrk, _trackingCell(row), align: Alignment.centerLeft),
      for (var i = 0; i < 3; i++) ...[
        _cell(
            _wMon,
            _scoreCell(i, rowId, maxScore, name, ReviewStage.selfRating,
                canEdit: widget.canEditSelf)),
        _cell(_wMon, _reviewCell(i, row)),
        _cell(
            _wMon,
            _scoreCell(i, rowId, maxScore, name, ReviewStage.managementReview,
                canEdit: (r) =>
                    widget.canEditManagement(r) && !r.isManagementLocked)),
      ],
      _cell(
          _wQtr,
          Text(
              _fmt(
                  qAvgRow((r) => widget.pct(r, rowId, ReviewStage.selfRating))),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
      _cell(
          _wQtr,
          Text(_fmt(qAvgRow((r) => _reviewPct(r, rowId))),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
      _cell(
          _wQtr,
          Text(_fmt(qAvgRow((r) => _rowFinalPct(r, rowId))),
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppColors.primaryPurple))),
    ]);
  }

  Widget _kraNameBlock(dynamic row) {
    final cat = row.category as String?;
    final rowId = row.id as String;
    final name = row.name as String;
    final KraReviewer? reviewer = row.reviewerGroup as KraReviewer?;
    final expanded = _expanded.contains(rowId);
    final justified = _anyJustified(rowId);
    final color = justified ? AppColors.success : AppColors.primaryPurple;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cat != null && cat.isNotEmpty)
          Text(cat,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentOrange)),
        Text(name,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        if (reviewer != null) ...[
          const SizedBox(height: 4),
          _reviewerBadge(reviewer),
        ],
        const SizedBox(height: 6),
        // Expand toggle for the per-month Reason & Proof line item.
        InkWell(
          onTap: () => setState(() {
            if (expanded) {
              _expanded.remove(rowId);
            } else {
              _expanded.add(rowId);
            }
          }),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: color.withValues(alpha: 0.08),
              border: Border.all(color: color.withValues(alpha: 0.30)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 14,
                  color: color),
              const SizedBox(width: 3),
              Flexible(
                child: Text('Reason & proof',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
              if (justified) ...[
                const SizedBox(width: 3),
                const Icon(Icons.check_circle_rounded,
                    size: 11, color: AppColors.success),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  // Target in its own column beside the KRA — shown in full (no truncation).
  Widget _targetCell(dynamic row) {
    final target = row.target as String?;
    if (target == null || target.trim().isEmpty) {
      return Text('—',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted));
    }
    return Text(target.trim(),
        style: TextStyle(
            fontSize: 11.5,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary));
  }

  // Tracking method in its own column — shown in full (no truncation).
  Widget _trackingCell(dynamic row) {
    final tracking = row.trackingMethod as String?;
    if (tracking == null || tracking.trim().isEmpty) {
      return Text('—',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted));
    }
    return Text(tracking.trim(),
        style:
            TextStyle(fontSize: 11, height: 1.3, color: AppColors.textMuted));
  }

  Widget _scoreCell(int monthIdx, String rowId, double maxScore, String name,
      ReviewStage stage,
      {required bool Function(MonthlyReview) canEdit}) {
    final review = widget.reviews[monthIdx];
    final p = widget.pct(review, rowId, stage);
    final editable = review != null && canEdit(review);

    // Management review inherits the Review-cycle score. Once this KRA's
    // assigned reviewer has rated it (Review done) and management hasn't
    // entered an override yet, pre-fill the Mgmt cell with that Review score so
    // management starts from it — accept it as-is or change it. The Qtr Final
    // already falls back to the Review score, so this just surfaces the value
    // that's effectively standing and seeds the editor with it. It's shown
    // muted + italic until management saves, so an inherited value reads apart
    // from one management has actually set.
    final double? reviewPct = stage == ReviewStage.managementReview
        ? _reviewPct(review, rowId)
        : null;
    final bool inheritsReview = editable && p == null && reviewPct != null;
    final double? shownPct = inheritsReview ? reviewPct : p;

    final text = Text(_fmt(shownPct),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          fontStyle: inheritsReview ? FontStyle.italic : FontStyle.normal,
          color: inheritsReview
              ? AppColors.primaryPurple.withValues(alpha: 0.55)
              : (editable ? AppColors.primaryPurple : AppColors.textSecondary),
        ));
    if (!editable) return text;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => widget.onEdit(
        review: review,
        rowId: rowId,
        maxScore: maxScore,
        stage: stage,
        currentPct: shownPct,
        kraName: name,
        monthLabel: widget.months[monthIdx].shortLabel,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: AppColors.primaryPurple.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: text),
          const SizedBox(width: 2),
          Icon(Icons.edit_rounded,
              size: 10, color: AppColors.primaryPurple.withValues(alpha: 0.7)),
        ]),
      ),
    );
  }

  // Small pill under a KRA name showing which reviewer owns it in the Review
  // cycle. Makes the per-KRA assignment visible on the sheet.
  Widget _reviewerBadge(KraReviewer reviewer) {
    final color = _reviewerColor(reviewer);
    return ConstrainedBox(
      // Never wider than the KRA column, so a long label clips instead of
      // overflowing the fixed grid.
      constraints: const BoxConstraints(maxWidth: _wKra - 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_reviewerIcon(reviewer), size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text('Reviewed by ${reviewer.shortLabel}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
      ),
    );
  }

  // True when the current viewer owns [stage] for this review: RM by
  // relationship, HR / Accounts by role.
  bool _canEditReviewerStage(MonthlyReview review, ReviewStage stage) {
    switch (stage) {
      case ReviewStage.reportingManagerRating:
        return widget.canEditManager(review);
      case ReviewStage.accountHrRating:
        return widget.canEditHr(review);
      case ReviewStage.financeRating:
        return widget.canEditFinance(review);
      default:
        return false;
    }
  }

  // The Review-cycle cell for ONE KRA/month. Each KRA is assigned to exactly
  // ONE reviewer (Reporting Manager / HR / Accounts) — never an average — so
  // this cell shows that single reviewer's rating and is editable only by them.
  // Until they've rated, it shows an explicit "<reviewer> pending" status.
  Widget _reviewCell(int monthIdx, dynamic row) {
    final review = widget.reviews[monthIdx];
    final rowId = row.id as String;
    // Every row resolves to a single reviewer (see _applyReviewerMap); a bare
    // row passed straight through (tests) defaults to the reporting manager.
    final KraReviewer reviewer =
        (row.reviewerGroup as KraReviewer?) ?? KraReviewer.reportingManager;
    final ReviewStage stage =
        (row.reviewStage as ReviewStage?) ?? ReviewStage.reportingManagerRating;
    if (review == null) {
      return Text(_fmt(null),
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.textSecondary));
    }
    final maxScore = (row.maxScore as num).toDouble();
    final name = row.name as String;
    final p = widget.pct(review, rowId, stage);
    final editable = _canEditReviewerStage(review, stage);
    final color = _reviewerColor(reviewer);

    void openEditor() => widget.onEdit(
          review: review,
          rowId: rowId,
          maxScore: maxScore,
          stage: stage,
          currentPct: p,
          kraName: name,
          monthLabel: widget.months[monthIdx].shortLabel,
        );

    // Already rated → show the reviewer's single score.
    if (p != null) {
      final text = Text(_fmt(p),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: editable ? color : AppColors.textSecondary,
          ));
      if (!editable) return text;
      return _reviewTapBox(
        color: color,
        onTap: openEditor,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: text),
          const SizedBox(width: 2),
          Icon(Icons.edit_rounded,
              size: 10, color: color.withValues(alpha: 0.85)),
        ]),
      );
    }

    // Not rated yet, and YOU are the assigned reviewer → a "Rate" affordance.
    if (editable) {
      return _reviewTapBox(
        color: color,
        onTap: openEditor,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text('Rate',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 11.5, color: color)),
          ),
          const SizedBox(width: 2),
          Icon(Icons.add_rounded, size: 12, color: color),
        ]),
      );
    }

    // Not rated yet, view-only → the pending status, naming WHO must rate it.
    return _pendingChip(reviewer);
  }

  // Bordered, tappable box shared by the rated-editable and "Rate" states.
  Widget _reviewTapBox({
    required Color color,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: child,
      ),
    );
  }

  // "<reviewer> review pending" — a compact amber chip (clock + short tag) that
  // tells the viewer exactly which reviewer this KRA is still waiting on.
  Widget _pendingChip(KraReviewer reviewer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: AppColors.warning.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.30)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.schedule_rounded, size: 10, color: AppColors.warning),
        const SizedBox(width: 3),
        Flexible(
          child: Text(reviewer.cellTag,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.warning)),
        ),
      ]),
    );
  }

  // The expandable Reason & Proof panel. Fills the viewport width and lays the
  // three months out as cards that WRAP — 3-across on a wide screen (everything
  // in one view), gracefully down to one column on a phone. Each month card
  // holds the employee's evidence and, for an assigned KRA, its reviewer's.
  Widget _lineItem(dynamic row) {
    final rowId = row.id as String;
    final name = row.name as String;
    final reviewer = row.reviewerGroup as KraReviewer?;
    final screenW = MediaQuery.of(context).size.width;
    // Fill the viewport minus the weight-column inset, not a fixed 560.
    final panelW = (screenW - _wWt - 30).clamp(260.0, 1180.0).toDouble();
    // Columns per row: 3 on a wide screen, 2 on a tablet, 1 on a phone.
    final cols = panelW >= 840 ? 3 : (panelW >= 560 ? 2 : 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_wWt + 6, 12, 14, 14),
      child: SizedBox(
        width: panelW,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.sticky_note_2_outlined,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text('Reason & proof',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'employee + reviewer evidence · one per month · reason ≤ 300 chars',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 10),
            // Cards laid out in rows of `cols`. Each row is an IntrinsicHeight +
            // stretch Row, so every card in it is the SAME height (aligned
            // borders) regardless of how much evidence it holds; the last row
            // is padded so a lone card keeps the same width as the others.
            for (var start = 0; start < 3; start += cols) ...[
              if (start > 0) const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < cols; c++) ...[
                      if (c > 0) const SizedBox(width: 12),
                      Expanded(
                        child: (start + c) < 3
                            ? _monthCard(row, start + c, rowId, name, reviewer)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _monthCard(
      dynamic row, int i, String rowId, String name, KraReviewer? reviewer) {
    final review = widget.reviews[i];
    final label = widget.months[i].shortLabel;
    final ReviewStage? rs = row.reviewStage as ReviewStage?;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryPurple)),
          ),
          const SizedBox(height: 8),
          if (review == null)
            Text('Not generated yet',
                style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic))
          else ...[
            _evidenceTile(review, rowId, name, label, ReviewStage.selfRating,
                'Employee', Icons.person_rounded, widget.canEditSelf(review)),
            if (rs != null) ...[
              // Min gap + a Spacer pins the reviewer tile to the card's bottom;
              // since the row's cards share a height, the reviewer tiles line
              // up across all three months regardless of the employee entry.
              const SizedBox(height: 8),
              const Spacer(),
              _evidenceTile(
                  review,
                  rowId,
                  name,
                  label,
                  rs,
                  'Reviewer · ${reviewer?.shortLabel ?? ''}',
                  Icons.how_to_reg_rounded,
                  _canEditReviewerStage(review, rs)),
            ],
          ],
        ],
      ),
    );
  }

  // One evidence slot (employee's or a reviewer's) inside a month card.
  Widget _evidenceTile(
      MonthlyReview review,
      String rowId,
      String name,
      String monthLabel,
      ReviewStage stage,
      String roleLabel,
      IconData roleIcon,
      bool canEdit) {
    final s = _rowIn(review, rowId)?.scoreFor(stage);
    final reason = s?.remark?.trim() ?? '';
    final fileName = widget.fileNameFor(review, rowId, stage);
    final filled = reason.isNotEmpty || fileName != null;
    final prompt = filled
        ? (reason.isNotEmpty ? reason : 'Attachment added')
        : (canEdit ? 'Add reason & proof' : 'No entry');
    final promptColor = filled
        ? AppColors.textPrimary
        : (canEdit ? AppColors.primaryPurple : AppColors.textMuted);
    return Material(
      color: filled
          ? AppColors.primaryPurple.withValues(alpha: 0.04)
          : AppColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onJustify(
          review: review,
          rowId: rowId,
          stage: stage,
          kraName: name,
          monthLabel: '$monthLabel · $roleLabel',
          canEdit: canEdit,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(roleIcon, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(roleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.2)),
                ),
                Icon(canEdit ? Icons.edit_rounded : Icons.visibility_rounded,
                    size: 13, color: AppColors.textMuted),
              ]),
              const SizedBox(height: 4),
              Text(prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: filled ? FontWeight.w500 : FontWeight.w700,
                      color: promptColor)),
              if (fileName != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.attach_file_rounded,
                      size: 11, color: AppColors.primaryPurple),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textSecondary)),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _totalsRow() {
    const t = TextStyle(fontWeight: FontWeight.w800, fontSize: 12);
    // Weighted monthly Review total and Final total, plus their quarter means.
    double monthReview(int i) => widget.reviews[i]?.reviewWeightedPct ?? 0;
    double monthFinal(int i) => widget.reviews[i]?.finalScorePct ?? 0;
    double qReview() => (monthReview(0) + monthReview(1) + monthReview(2)) / 3;
    double qFinal() => (monthFinal(0) + monthFinal(1) + monthFinal(2)) / 3;
    return Container(
      decoration:
          BoxDecoration(color: AppColors.primaryPurple.withValues(alpha: 0.06)),
      child: Row(children: [
        _cell(
            _wWt,
            const Text('100%',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
            align: Alignment.centerLeft),
        _cell(_wKra, const Text('Total', style: t),
            align: Alignment.centerLeft),
        _cell(_wTgt, const SizedBox.shrink(), align: Alignment.centerLeft),
        _cell(_wTrk, const SizedBox.shrink(), align: Alignment.centerLeft),
        for (var i = 0; i < 3; i++) ...[
          _cell(
              _wMon,
              Text('${widget.monthTotal(i, ReviewStage.selfRating).round()}%',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12))),
          _cell(
              _wMon,
              Text('${monthReview(i).round()}%',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppColors.accentOrange))),
          _cell(
              _wMon,
              Text(
                  '${widget.monthTotal(i, ReviewStage.managementReview).round()}%',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12))),
        ],
        _cell(_wQtr,
            Text('${widget.qAvg(ReviewStage.selfRating).round()}%', style: t)),
        _cell(
            _wQtr,
            Text('${qReview().round()}%',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: AppColors.accentOrange))),
        _cell(
            _wQtr,
            Text('${qFinal().round()}%',
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: AppColors.primaryPurple))),
      ]),
    );
  }
}

class _PayoutCard extends StatelessWidget {
  final double qSelf;
  final double qFinal;
  final double eligibleMonthly;
  final double quarterEligible;
  final double payout;
  const _PayoutCard({
    required this.qSelf,
    required this.qFinal,
    required this.eligibleMonthly,
    required this.quarterEligible,
    required this.payout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(AppStrings.quarterlyPayoutTitle,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 12),
          _row('Quarter self average', '${qSelf.round()}%'),
          _row('Quarter final average', '${qFinal.round()}%'),
          _row('Monthly incentive',
              EmployeeFormatters.currencyInr(eligibleMonthly)),
          _row('Quarter eligible (×3)',
              EmployeeFormatters.currencyInr(quarterEligible)),
          const Divider(height: 20),
          _row(
            AppStrings.quarterlyPayoutAmount,
            EmployeeFormatters.currencyInr(payout),
            emphasize: true,
          ),
          const SizedBox(height: 4),
          Text(
            'Payout = monthly incentive × 3 × quarter final average '
            '(management override, else the Review average).',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: emphasize ? 14 : 12.5,
                  fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
                  color: emphasize
                      ? AppColors.textPrimary
                      : AppColors.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontSize: emphasize ? 16 : 13,
                  fontWeight: FontWeight.w800,
                  color: emphasize
                      ? AppColors.primaryPurple
                      : AppColors.textPrimary)),
        ],
      ),
    );
  }
}

/// Accessible rating picker shown as a bottom sheet. Big slider + one-tap
/// preset chips (which save immediately) replace the old "tap pen → type →
/// tap Save" dialog. Pops the chosen 0–100 value, or null on cancel.
class _RatingSheet extends StatefulWidget {
  final String kraName;
  final String monthLabel;
  final String stageLabel;
  final double? currentPct;

  /// Hard ceiling for this rating, or null for the full 0–100 range.
  ///
  /// Used by the reporting-manager column, which may not exceed the employee's
  /// own score for the same KRA: a manager moderates a self-assessment downward,
  /// never inflates it. Enforced on the slider, the presets AND the commit, so
  /// there is no route past it.
  final double? maxPct;
  final String? capNote;
  const _RatingSheet({
    required this.kraName,
    required this.monthLabel,
    required this.stageLabel,
    required this.currentPct,
    this.maxPct,
    this.capNote,
  });

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  late double _val;

  /// The ceiling, normalised into range. Never null so callers can clamp freely.
  double get _ceiling => (widget.maxPct ?? 100).clamp(0, 100).toDouble();

  @override
  void initState() {
    super.initState();
    _val = (widget.currentPct ?? 0).clamp(0, _ceiling).toDouble();
  }

  void _commit(double v) =>
      Navigator.of(context).pop(v.clamp(0, _ceiling).toDouble());

  @override
  Widget build(BuildContext context) {
    const presets = [0, 25, 50, 75, 90, 100];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.dividerStrong,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(
              '${widget.monthLabel} · ${widget.stageLabel}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.3),
            ),
            const SizedBox(height: 3),
            Text(
              widget.kraName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),
            Center(
              child: ShaderMask(
                shaderCallback: (r) => AppGradients.ribbon.createShader(r),
                child: Text(
                  '${_val.round()}%',
                  style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.primaryPurple,
                inactiveTrackColor: AppColors.surfaceOverlay,
                thumbColor: AppColors.primaryPurpleLight,
                overlayColor: AppColors.primaryPurple.withValues(alpha: 0.14),
                trackHeight: 5,
              ),
              child: Slider(
                value: _val,
                max: 100,
                divisions: 100,
                label: '${_val.round()}%',
                // Clamped rather than capping the slider's own `max`, so the
                // track still shows the full 0-100 scale and the ceiling reads as
                // a limit rather than a rescaled axis. Also avoids a degenerate
                // min == max slider when the ceiling is 0.
                onChanged: (v) =>
                    setState(() => _val = v.clamp(0, _ceiling).toDouble()),
              ),
            ),
            if (widget.capNote != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 13, color: AppColors.accentOrange),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      widget.capNote!,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentOrange),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text('Quick set',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5)),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in presets)
                  // Presets SET the value; they no longer save on tap. Every
                  // rating — self, the stage-2 reviewers and management — now
                  // commits through the explicit Save button below, so a stray
                  // tap can't write a score.
                  //
                  // A preset above the ceiling is shown disabled rather than
                  // hidden, so the manager can see the limit instead of
                  // wondering where the option went.
                  _PresetChip(
                    percent: p,
                    selected: _val.round() == p,
                    enabled: p <= _ceiling,
                    onTap: () => setState(() => _val = p.toDouble()),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => _commit(_val),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Save ${_val.round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The employee's "I'm done" action, at the end of the ratings.
///
/// Deliberately a prominent filled button rather than one more tap-target in the
/// grid: it is the only irreversible thing the employee does on this screen —
/// it moves the review to their manager and emails them.
class _SubmitSelfRatingBar extends StatefulWidget {
  final Future<void> Function() onSubmit;
  const _SubmitSelfRatingBar({required this.onSubmit});

  @override
  State<_SubmitSelfRatingBar> createState() => _SubmitSelfRatingBarState();
}

class _SubmitSelfRatingBarState extends State<_SubmitSelfRatingBar> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onSubmit();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.task_alt_rounded,
                  size: 18, color: AppColors.primaryPurple),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  AppStrings.selfSubmitHint,
                  style: TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text(
              AppStrings.selfSubmitAction,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Your manager sent this month back" — who, when, and why.
///
/// The reason is the whole point: without it the employee sees their sheet
/// reopen with no idea what to change. Rendered for every viewer, so the return
/// is visible to HR and management as part of the review's history too.
class _ReworkNotice extends StatelessWidget {
  final String monthLabel;
  final StageRecord record;
  const _ReworkNotice({required this.monthLabel, required this.record});

  @override
  Widget build(BuildContext context) {
    final by = record.actorName.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.accentOrange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.accentOrange.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.assignment_return_rounded,
                size: 16, color: AppColors.accentOrange),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    by.isEmpty
                        ? '$monthLabel · sent back for rework'
                        : '$monthLabel · sent back by $by',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accentOrange,
                    ),
                  ),
                  if ((record.comment ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      record.comment!.trim(),
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reporting manager's "send the self-rating back" action.
///
/// Separate from the rating cells on purpose: returning the work is a decision
/// about the whole month, not one KRA, and it is destructive enough to the
/// employee's flow that it should not sit inside a tap-to-rate cell.
class _ReworkBar extends StatefulWidget {
  final Future<void> Function() onSendBack;
  const _ReworkBar({required this.onSendBack});

  @override
  State<_ReworkBar> createState() => _ReworkBarState();
}

class _ReworkBarState extends State<_ReworkBar> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onSendBack();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.undo_rounded,
              size: 18, color: AppColors.accentOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppStrings.sheetReworkMessage,
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _busy ? null : _run,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentOrange,
              side: const BorderSide(color: AppColors.accentOrange),
            ),
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(AppStrings.sheetReworkAction),
          ),
        ],
      ),
    );
  }
}

/// Asks the manager WHY the self-rating is going back. The reason is required —
/// an unexplained return leaves the employee guessing what to change, and it is
/// the only thing that reaches them.
class _ReworkReasonDialog extends StatefulWidget {
  const _ReworkReasonDialog();

  @override
  State<_ReworkReasonDialog> createState() => _ReworkReasonDialogState();
}

class _ReworkReasonDialogState extends State<_ReworkReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = AppStrings.sheetReworkReasonRequired);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: const Text(AppStrings.sheetReworkTitle,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.sheetReworkMessage,
              style:
                  TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: AppStrings.sheetReworkReasonLabel,
              hintText: AppStrings.sheetReworkReasonHint,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          style:
              FilledButton.styleFrom(backgroundColor: AppColors.accentOrange),
          child: const Text(AppStrings.sheetReworkConfirm),
        ),
      ],
    );
  }
}

/// One "quick set" chip in the rating sheet. Sets the pending value — it does
/// not save; that is the Save button's job. Disabled when the percentage is
/// above the rating's ceiling (see [_RatingSheet.maxPct]).
class _PresetChip extends StatelessWidget {
  final int percent;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _PresetChip({
    required this.percent,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final base = enabled ? AppColors.primaryPurple : AppColors.textMuted;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: base.withValues(alpha: selected ? 0.28 : 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: base.withValues(alpha: selected ? 0.85 : 0.30),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          '$percent%',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: enabled
                ? AppColors.primaryPurpleLight
                : AppColors.textMuted,
            decoration: enabled ? null : TextDecoration.lineThrough,
          ),
        ),
      ),
    );
  }
}

class _SheetError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _SheetError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryPurple,
                side: const BorderSide(color: AppColors.primaryPurple),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ShimmerBox(height: 90, borderRadius: 16),
        SizedBox(height: 16),
        ShimmerBox(height: 260, borderRadius: 12),
        SizedBox(height: 16),
        ShimmerBox(height: 160, borderRadius: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Per-KRA "Reason & Proof" line item (employee edits; manager/HR view)
// ─────────────────────────────────────────────────────────────────────

/// What the justification editor returns on Save.
class _JustificationResult {
  final String reason;
  final ({String name, Uint8List? bytes})? file;
  const _JustificationResult({
    required this.reason,
    required this.file,
  });
}

/// Employee editor for one month's Reason (≤300 chars) + Proof attachment.
class _JustificationDialog extends StatefulWidget {
  final String kraName;
  final String monthLabel;
  final String initialReason;
  final ({String name, Uint8List? bytes})? initialFile;

  const _JustificationDialog({
    required this.kraName,
    required this.monthLabel,
    required this.initialReason,
    required this.initialFile,
  });

  @override
  State<_JustificationDialog> createState() => _JustificationDialogState();
}

class _JustificationDialogState extends State<_JustificationDialog> {
  late final TextEditingController _reason;
  ({String name, Uint8List? bytes})? _file;

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController(text: widget.initialReason);
    _file = widget.initialFile;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Max attachment size (raw bytes).
  ///
  /// INTERIM VALUE — sized to fit under the LIVE server's 1 MB request-body
  /// limit, so attachments work today without waiting on a deploy. A base64
  /// upload is ~4/3 of the raw bytes plus a small JSON envelope, so ~700 KB raw
  /// → ~0.95 MB body, safely under 1 MB. Once the server's `src/app.js` limit is
  /// raised to 10 MB (already coded, not yet deployed) this should go back to
  /// 5 MB (and the server's PROOF_FILE_MAX_BASE64 to ~7 MB) for Office files.
  static const int _maxProofBytes = 700 * 1024;

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickFile() async {
    // Every failure path below used to be a silent `return`, which is
    // indistinguishable from "the button is dead". Say something instead.
    try {
      // `withData: true` is what makes this work on the WEB build. A browser
      // never exposes a filesystem path, so `PlatformFile.path` is ALWAYS null
      // there — the old `if (path == null) return;` meant picking a file
      // silently did nothing at all on web. Bytes are the portable
      // representation (and are what the upload needs anyway).
      // Any file type — Excel, Word, PowerPoint, images, PDF, whatever the
      // employee's evidence happens to be. Restricting extensions just blocked
      // legitimate proof; the size cap below is the real guard.
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return; // user cancelled — normal
      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null) {
        _say('Could not read "${f.name}". Try another file.');
        return;
      }
      if (bytes.length > _maxProofBytes) {
        final kb = (bytes.length / 1024).round();
        _say('"${f.name}" is $kb KB — attachments are capped at ~700 KB for '
            'now (raised once the server upload limit is deployed).');
        return;
      }
      setState(() => _file = (name: f.name, bytes: bytes));
    } catch (e) {
      _say('Could not open the file picker: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reason & Proof · ${widget.monthLabel}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.kraName,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              minLines: 3,
              maxLines: 5,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: AppStrings.ratingReasonLabel,
                hintText: AppStrings.ratingReasonHint,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            _FilePickRow(
              file: _file,
              onPick: _pickFile,
              onRemove: () => setState(() => _file = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_JustificationResult(
            reason: _reason.text,
            file: _file,
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The "Attach proof file" control — add button, or the picked-file chip with
/// replace/remove and a note that the file is local-only for now.
class _FilePickRow extends StatelessWidget {
  final ({String name, Uint8List? bytes})? file;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _FilePickRow({
    required this.file,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.attach_file_rounded, size: 18),
          label: const Text(AppStrings.ratingProofFileAdd),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryPurple,
            side: BorderSide(color: AppColors.divider),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primaryPurple.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined,
                  size: 18, color: AppColors.primaryPurple),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              TextButton(
                onPressed: onPick,
                child: const Text(AppStrings.ratingProofFileReplace),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: AppStrings.ratingProofFileRemove,
                icon: Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.ratingProofFileLocalNote,
          style: TextStyle(
              fontSize: 10.5, color: AppColors.textMuted, height: 1.3),
        ),
      ],
    );
  }
}

/// Shows a fetched proof attachment to whoever may view the review — the
/// employee, their reporting manager (whatever that manager's role), and
/// management.
///
/// Images preview inline, but EVERY type gets a Download button. Showing only a
/// filename and mime type meant a manager could see that a PDF/Excel/Word proof
/// existed yet had no way to actually open it — which is not "access to the
/// proof" at all.
class _ProofFileViewer extends StatelessWidget {
  final ProofFileDownload file;
  const _ProofFileViewer({required this.file});

  Future<void> _download(BuildContext context, Uint8List bytes) async {
    final ok = await saveProofFile(
      bytes: bytes,
      fileName: file.name,
      mime: file.mime,
    );
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Downloading is only supported in the web app.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isImage = file.mime.startsWith('image/');
    Uint8List? bytes;
    try {
      bytes = base64Decode(file.base64Data);
    } catch (_) {
      bytes = null;
    }
    return AlertDialog(
      title: const Text('Proof attachment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.name,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            if (isImage && bytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(bytes, fit: BoxFit.contain),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(children: [
                  const Icon(Icons.insert_drive_file_outlined,
                      color: AppColors.primaryPurple),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${file.mime} · attached by the employee',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ),
                ]),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        // Present for EVERY file type — this is what actually gives the
        // reporting manager / management access to the evidence.
        FilledButton.icon(
          onPressed: bytes == null ? null : () => _download(context, bytes!),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryPurple,
          ),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download'),
        ),
      ],
    );
  }
}

/// Read-only Reason + Proof attachment, shown to the reporting manager/HR/admin.
class _JustificationView extends StatelessWidget {
  final String kraName;
  final String monthLabel;
  final String reason;
  final String? fileName;

  /// Opens the stored attachment. Null when the employee filed none.
  final VoidCallback? onOpenFile;

  const _JustificationView({
    required this.kraName,
    required this.monthLabel,
    required this.reason,
    required this.fileName,
    this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reason & Proof · $monthLabel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kraName,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          _labelled('Reason',
              reason.trim().isEmpty ? AppStrings.ratingNoReason : reason.trim(),
              muted: reason.trim().isEmpty),
          const SizedBox(height: 12),
          Text('PROOF ATTACHMENT',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMuted,
                  letterSpacing: 0.6)),
          const SizedBox(height: 4),
          if (fileName != null)
            InkWell(
              onTap: onOpenFile,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined,
                      size: 16, color: AppColors.primaryPurple),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(fileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5, color: AppColors.textPrimary)),
                  ),
                  if (onOpenFile != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.open_in_new_rounded,
                        size: 15, color: AppColors.primaryPurple),
                  ],
                ],
              ),
            )
          else
            Text('No attachment uploaded.',
                style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _labelled(String label, String value, {required bool muted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
                letterSpacing: 0.6)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: muted ? AppColors.textMuted : AppColors.textPrimary)),
      ],
    );
  }
}
