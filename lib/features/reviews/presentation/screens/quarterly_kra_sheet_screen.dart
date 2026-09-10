import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/monthly_kra_row.dart';
import '../../data/models/monthly_review.dart';
import '../../../../core/enums/review_flow.dart';
import '../../data/models/review_flow.dart';
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

  /// Injectable clock, for the month-ratability gates.
  ///
  /// Whether a month may be rated depends on today's date, so the gates that
  /// enforce it cannot be tested deterministically against the real clock —
  /// they would assert something different every month. Null means
  /// `DateTime.now()`, so production is unaffected.
  @visibleForTesting
  final DateTime? clock;

  const QuarterlyKraSheetScreen({super.key, this.employeeId, this.clock});

  @override
  ConsumerState<QuarterlyKraSheetScreen> createState() =>
      _QuarterlyKraSheetScreenState();
}

class _QuarterlyKraSheetScreenState
    extends ConsumerState<QuarterlyKraSheetScreen> {
  ReviewPeriod? _anchor;
  bool _saving = false;

  /// Now, as the ratability gates see it. Read through a getter rather than
  /// captured in `initState` so a sheet left open across midnight — or across
  /// a month boundary, which is exactly when this rule changes — re-evaluates
  /// instead of holding a stale answer.
  DateTime get _now => widget.clock ?? DateTime.now();

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
      MonthlyReview? r, KraReviewerAssignment map, ReviewFlow flow) {
    if (r == null) return r;
    // Match the template's ordering so position-based fallback lines up.
    final ordered = [...r.rows]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final rows = <MonthlyKraRow>[
      for (var i = 0; i < ordered.length; i++)
        () {
          final row = ordered[i];
          // What the SERVER has for this row, as distinct from what the local
          // assignment template guesses. The difference decides whether a
          // re-point is safe — see below.
          final stored = row.reviewerGroup;
          var reviewer = stored ??
              map.byName[kraNameKey(row.name)] ??
              (i < map.byOrder.length ? map.byOrder[i] : null) ??
              defaultReviewerFor(flow);
          // A row assigned to a reviewer this flow does not use has NO eligible
          // rater — nobody can score it, and the cell offers no tap target to
          // anyone. Re-point it at a seat the flow actually has, but ONLY when
          // the server holds no assignment for the row.
          //
          // That condition is not caution, it is the server's rule. writeRowScores
          // carries a per-KRA reviewer guard in raw SQL: a Review-cycle rater may
          // only score a row assigned to them, and it passes any stage when
          // `reviewer_group IS NULL`. So re-pointing a row the server has STORED
          // as the reporting manager produces an ACCOUNT_HR_RATING write that
          // matches nothing, inserts zero rows, and — in its own words —
          // "Mismatches are silently skipped". HTTP 200, no error, no score.
          //
          // Faking a rateable cell there is worse than showing none: the rater
          // enters a value, sees it accepted, and finds it gone on the next
          // refresh. So leave it visibly on the seat the flow does not use, and
          // let the sheet say so — the fix is to reassign the KRA, which is what
          // an administrators-only organisation should have done anyway.
          //
          // Only ever redirects AWAY from a removed stage, so on the standard
          // flow (where every stage is present) this whole branch is a no-op.
          if (stored == null &&
              !stageIsInFlow(stageForReviewer(reviewer), flow)) {
            reviewer = defaultReviewerFor(flow);
          }
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
      // Bound to a local so the null check promotes it; `s?.value` cannot be
      // promoted through the null-aware access, which is why this previously
      // needed two bang operators to say something already proven.
      final value = row.scoreFor(stage)?.value;
      if (value != null && row.maxScore > 0) {
        return (value / row.maxScore) * 100;
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
    // A month that has not ENDED cannot be rated by anyone, including its own
    // employee. Enforced here as well as in isCellOpenForEntry because this
    // gate feeds `_submittableReviews`, and that is a far worse failure than an
    // open cell: with a score already present for the live month, the "Submit
    // self-rating" bar appeared, its dialog named that month, and confirming
    // advanced an unfinished month to the reporting-manager stage and notified
    // the manager and HR. Irreversible from the employee's side.
    //
    // The gate is still needed after the cell fix, because scores written for
    // the live month BEFORE that fix shipped are already in the database and
    // the submit loop would go on offering them.
    if (!r.period.isRatableOn(_now)) return false;
    // Some organisations run a pipeline with no self-rating at all. Checked
    // before identity: under that flow it is not that someone ELSE rates the
    // employee, it is that the stage does not exist.
    if (!stageIsInFlow(ReviewStage.selfRating, scope.reviewFlow)) return false;
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
    final flow = scope.reviewFlow;
    if (!stageIsInFlow(ReviewStage.reportingManagerRating, flow)) return false;
    // Under a flow that has taken rating out of the reporting line, this seat
    // is MANAGEMENT's — the KRAs left over once HR and Accounts have taken
    // theirs — and the question becomes "what role do you hold?", not "are you
    // this employee's manager?". Asking the relationship there would lock out
    // the only people the flow grants it to.
    if (!stageIsRelationshipGated(ReviewStage.reportingManagerRating, flow)) {
      return canActOnStage(
          ReviewStage.reportingManagerRating, flow, scope.effectiveRoles);
    }
    return r.managerId != null && r.managerId == scope.userId;
  }

  // The three Review-cycle raters are entered in parallel. Two are gated by
  // ROLE (HR, Accounts); the reporting-manager one stays a RELATIONSHIP (above).
  bool _canEditHr(MonthlyReview r, ReviewScope? scope) =>
      canRateReviewStage(ReviewStage.accountHrRating, scope, r);
  bool _canEditFinance(MonthlyReview r, ReviewScope? scope) =>
      canRateReviewStage(ReviewStage.financeRating, scope, r);

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
      // Reads the MODEL's answer rather than restating a role list, which is
      // how `management` — the stage's primary actor — came to be missing here
      // while `managementReview.actorRoles` named it all along: the founder /
      // CEO tier could not open the sign-off UI it exclusively owns. Deriving
      // the gate means the two can no longer drift apart, and the
      // FeatureFlags.roleTiers narrowing is honoured for free.
      canActOnStage(
          ReviewStage.managementReview, scope.reviewFlow, scope.effectiveRoles);

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
      final selfValue =
          _currentScore(review, rowId, ReviewStage.selfRating)?.value;
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
  String _saveErrorText(Object e,
          [String fallback = 'Could not save. Please try again.']) =>
      e is ApiError ? e.combinedMessage : fallback;

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

  // ── The reporting manager's own submit ────────────────────────────────────
  //
  // The manager's counterpart to the employee's "Submit self-rating". Their
  // per-KRA scores already persist the moment the rating sheet closes, so this
  // adds the missing "I'm done" step rather than any new score writing.
  //
  // Scoped to the manager's OWN ratings. Each KRA is assigned to exactly one
  // Review-cycle reviewer ([MonthlyKraRow.reviewStage]), and the three raters
  // work in parallel on separate stages, so submitting
  // `REPORTING_MANAGER_RATING` finalises this manager's KRAs and leaves HR's
  // and Accounts' rows untouched for them to submit themselves.

  /// Months whose manager review this viewer may submit. The per-review rule
  /// itself lives in [managerCanSubmitReview] so it can be tested directly.
  List<MonthlyReview> _managerSubmittableReviews(
    List<MonthlyReview?> reviews,
    ReviewScope? scope,
  ) =>
      // No manager rating in this flow means nothing for a manager to submit.
      // Checked here rather than inside managerCanSubmitReview so that rule
      // stays a pure function of the review and the viewer.
      scope == null ||
              !stageIsInFlow(
                  ReviewStage.reportingManagerRating, scope.reviewFlow)
          ? const []
          : [
              for (final r in reviews.whereType<MonthlyReview>())
                if (managerCanSubmitReview(r, scope.userId, now: _now)) r,
            ];

  /// The manager-submit action, or null when there is nothing to submit — which
  /// keeps the bar off employees' own sheets, off other managers' reports, and
  /// off months already submitted or not yet rated.
  Future<void> Function()? _managerSubmitAction(
    List<MonthlyReview?> reviews,
    ReviewScope? scope,
  ) {
    if (scope == null) return null;
    final targets = _managerSubmittableReviews(reviews, scope);
    if (targets.isEmpty) return null;
    return () => _submitManagerReview(targets, scope);
  }

  /// Submits the reporting manager's review for [targets] and confirms it.
  Future<void> _submitManagerReview(
    List<MonthlyReview> targets,
    ReviewScope scope,
  ) async {
    final months = targets.map((r) => r.period.label).join(', ');
    // Coverage across the quarter, so "3 of 5" reads correctly for a
    // multi-month submit rather than quoting only the first month.
    final rated =
        targets.fold<int>(0, (sum, r) => sum + managerRatedKraCount(r));
    final total =
        targets.fold<int>(0, (sum, r) => sum + managerAssignedKras(r).length);

    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.mgrSubmitConfirmTitle,
      message: '${AppStrings.mgrSubmitConfirmMessage}\n\n'
          '${AppStrings.mgrSubmitCoverage(rated, total)}\n\n$months',
      confirmLabel: AppStrings.mgrSubmitConfirmAction,
      cancelLabel: AppStrings.commonCancel,
      icon: Icons.task_alt_rounded,
      accentColor: AppColors.primaryPurple,
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(monthlyReviewRepositoryProvider);
      for (final review in targets) {
        // approved: true is what separates this from the rework send-back,
        // which posts the same stage with approved: false.
        await repo.submitStage(
          review.id,
          ReviewStage.reportingManagerRating,
          approved: true,
          actorId: scope.userId,
          actorName: scope.userName,
        );
      }
      ref.invalidate(quarterlySheetProvider);
      // The manager's team list badges review state from the summary.
      ref.invalidate(monthlyReviewListProvider);
      if (mounted) await _showManagerSubmittedDialog();
    } catch (e) {
      if (mounted) {
        final conflict = e is ApiError && e.statusCode == 409;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(conflict
                ? AppStrings.mgrSubmitAlreadyMoved
                : '${AppStrings.mgrSubmitFailed} '
                    '${e is ApiError ? e.message : e}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showManagerSubmittedDialog() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          icon: const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 44),
          title: const Text(
            AppStrings.mgrSubmitDoneTitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          content: Text(
            AppStrings.mgrSubmitDoneMessage,
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
        // Handing the sheet back asks the EMPLOYEE to revise their own
        // self-rating. A flow with no self-rating has nothing to hand back and
        // nobody to hand it to, so the action must not be offered there — it
        // would move the review backwards into a stage that admits no actor and
        // strand it.
        if (stageIsInFlow(
            ReviewStage.selfRating, scope?.reviewFlow ?? ReviewFlow.standard))
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
            .showSnackBar(SnackBar(content: Text(_saveErrorText(e))));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                _saveErrorText(e, 'Could not reopen. Please try again.'))));
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
            .showSnackBar(SnackBar(content: Text(_saveErrorText(e))));
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
            for (final r in data.reviews)
              _applyReviewerMap(
                  r, reviewerMap, scope?.reviewFlow ?? ReviewFlow.standard),
          ];
          final canManage = _hasManagementRole(scope);
          return _Sheet(
            months: data.months,
            reviews: mappedReviews,
            flow: scope?.reviewFlow ?? ReviewFlow.standard,
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
            // The reporting manager's counterpart, scoped to their own KRAs.
            onSubmitManagerReview: _managerSubmitAction(mappedReviews, scope),
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

// ── The reporting manager's submit rule ──────────────────────────────────────
//
// Top-level and visible for testing because "submit only MY ratings" is the
// whole point of the manager's submit, and that scoping deserves a direct test
// rather than being reachable only through a rendered widget.

/// The KRAs on [r] assigned to the reporting manager.
///
/// A row with no assigned reviewer (legacy data) falls back to the reporting
/// manager, matching how the Review column itself resolves a row's stage.
@visibleForTesting
List<MonthlyKraRow> managerAssignedKras(MonthlyReview r) => [
      for (final row in r.rows)
        if ((row.reviewStage ?? ReviewStage.reportingManagerRating) ==
            ReviewStage.reportingManagerRating)
          row,
    ];

/// How many of the manager's own KRAs carry a manager score. Surfaced in the
/// confirm dialog so submitting a partly-rated month is a deliberate choice.
@visibleForTesting
int managerRatedKraCount(MonthlyReview r) => managerAssignedKras(r)
    .where((row) =>
        row.scoreFor(ReviewStage.reportingManagerRating)?.value != null)
    .length;

/// Whether [managerUserId] may submit their reporting-manager review of [r].
///
/// Mirrors the employee's rule, scoped to the manager's own KRAs:
///   * they are this review's reporting manager (a RELATIONSHIP, not a role)
///     and the month is not already completed;
///   * at least one KRA assigned to THEM carries their score — submitting an
///     untouched month would finalise an empty review. HR's and Accounts' rows
///     are ignored here, so rating an HR-assigned KRA never unlocks the
///     manager's submit;
///   * they have not already submitted, which a stage record for
///     `REPORTING_MANAGER_RATING` proves, so the button goes away once used.
///
/// Deliberately NOT gated on the cursor still sitting at the manager's stage,
/// for the same reason the employee's rule isn't: a backend that auto-advances
/// on save moves the cursor before submit is ever pressed, and the window would
/// never open. A server that disagrees is handled on the response (409).
@visibleForTesting

/// The identity test requires a NON-EMPTY id on both sides. A review with a
/// blank `managerId` would otherwise match a viewer with a blank `userId` and
/// hand them the submit — unlikely, but it fails open, so it is ruled out here.
bool managerCanSubmitReview(
  MonthlyReview r,
  String managerUserId, {
  required DateTime now,
}) =>
    // A month that has not ended must not be submitted. Submitting freezes a
    // partial rating: it advances the review, snapshots the weighted manager
    // percentage into the computed score, and makes the bar vanish (the
    // stage-record test below goes false) before the month it covers is over.
    //
    // Note what was NOT wrong: the POST targets the right review id and the
    // confirmation dialog names the right month. The defect is purely that it
    // was offered too early.
    r.period.isRatableOn(now) &&
    !r.isComplete &&
    managerUserId.isNotEmpty &&
    (r.managerId ?? '').isNotEmpty &&
    r.managerId == managerUserId &&
    managerRatedKraCount(r) > 0 &&
    r.recordFor(ReviewStage.reportingManagerRating) == null;

/// Builds the quarterly-sheet body from plain data (no providers/auth) so
/// widget tests can exercise its layout in isolation — e.g. assert the grid
/// renders a full "100%" editable cell without a RenderFlex overflow.
@visibleForTesting
Widget quarterlyKraSheetBodyForTest({
  required List<ReviewPeriod> months,
  required List<MonthlyReview?> reviews,

  /// Which pipeline the organisation runs. The sheet reads nothing else
  /// off the review scope, so this is the whole of it — and it decides
  /// whether the Self columns are drawn at all.
  ReviewFlow flow = ReviewFlow.standard,
  bool editableSelf = true,
  bool editableManager = false,
  bool editableHr = false,
  bool editableFinance = false,
  bool editableManagement = false,
  Future<void> Function()? onLockManagement,
  Future<void> Function()? onReopenManagement,
  Future<void> Function()? onSendBackForRework,
  Future<void> Function()? onSubmitSelfRating,
  Future<void> Function()? onSubmitManagerReview,

  /// Pins "today" so a test can assert the current-month copy deterministically.
  DateTime? now,

  /// Observes which (review, row, stage) an edit was aimed at. The row id in
  /// particular is worth asserting: it differs per month on the real backend,
  /// so a save handed the wrong one would target another month's row.
  void Function({
    required MonthlyReview review,
    required String rowId,
    required ReviewStage stage,
  })? onEdit,
}) {
  double? pct(MonthlyReview? r, String rowId, ReviewStage stage) {
    if (r == null) return null;
    for (final row in r.rows) {
      if (row.id != rowId) continue;
      // Bound to a local so the null check promotes it; `s?.value` cannot be
      // promoted through the null-aware access, which is why this previously
      // needed two bang operators to say something already proven.
      final value = row.scoreFor(stage)?.value;
      if (value != null && row.maxScore > 0) {
        return (value / row.maxScore) * 100;
      }
      return null;
    }
    return null;
  }

  return _Sheet(
    clock: now,
    months: months,
    reviews: reviews,
    flow: flow,
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
    }) async {
      onEdit?.call(review: review, rowId: rowId, stage: stage);
    },
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
    onSubmitManagerReview: onSubmitManagerReview,
  );
}

class _Sheet extends StatelessWidget {
  /// Stands in for "now" when deciding which month is the current one.
  ///
  /// Injectable because the sheet CHANGES ITS COPY around the current month, so
  /// a widget that read the wall clock directly would make that copy untestable
  /// — and would leave the tests quietly asserting something different every
  /// month.
  final DateTime? clock;
  final List<ReviewPeriod> months;
  final List<MonthlyReview?> reviews;

  /// The pipeline this organisation runs — the only thing the sheet ever
  /// needed off the review scope.
  ///
  /// Resolved ONCE by the screen and passed down, rather than each of the
  /// seven consumers below writing `scope?.reviewFlow ?? standard` for
  /// itself. That restating is what left the flow badge, the legend and
  /// the grid able to disagree about which pipeline was running.
  final ReviewFlow flow;
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

  /// The reporting manager's explicit "I'm done" for the KRAs assigned to
  /// them. Null unless they actually have a month of their own to submit.
  final Future<void> Function()? onSubmitManagerReview;

  const _Sheet({
    this.clock,
    required this.months,
    required this.reviews,
    required this.flow,
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
    this.onSubmitManagerReview,
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
    // Name the month that is actually outstanding rather than saying "this
    // sheet". The sheet covers a quarter, so a generic hint lets someone fill in
    // the wrong month, believe they are finished, and still be chased as overdue.
    final dueMonth = _currentMonthNeedingSelfRating(
        months, reviews, clock ?? DateTime.now());
    final scopeLabel = canSelf
        ? (dueMonth != null
            ? 'Rate your ${dueMonth.shortLabel} Self column — that month has '
                'closed and it is still empty.'
            : 'You can edit the Self ratings on this sheet.')
        : canMgr
            // The same seat reads differently in each pipeline. Under
            // administrators-only it is management picking up whatever HR and
            // Accounts were not assigned, so naming the reporting manager here
            // would describe a relationship the flow no longer uses.
            ? (stageIsRelationshipGated(
                    ReviewStage.reportingManagerRating, flow)
                ? 'You can rate the KRAs assigned to you as Reporting Manager — '
                    'tap a Review cell.'
                : 'You can rate the KRAs left to Management — the ones not '
                    'assigned to HR or Accounts. Tap a Review cell.')
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
                  // Which pipeline the sheet BELIEVES it is running.
                  //
                  // Shown unconditionally, including for the standard flow.
                  // Its absence cost a long debugging session: an organisation
                  // had been switched to administrators-only, the server was
                  // dropping the field from /auth/me, and the sheet was quietly
                  // running the standard pipeline — refusing every rating while
                  // it waited for a self-rating that flow does not have. The
                  // screen looked correct and said nothing. Naming the flow
                  // makes "the setting didn't reach me" and "you aren't allowed"
                  // two visibly different failures.
                  _FlowBadge(flow: flow),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _ReviewerLegend(flow: flow),
            ),
            // KRAs assigned to a reviewer this flow does not use. Nobody can
            // score them and the server would drop a score aimed anywhere else,
            // so say so plainly instead of leaving three rows that quietly
            // refuse every attempt.
            () {
              final stranded = kraNamesWithoutRaterInFlow(reviews, flow);
              if (stranded.isEmpty) return const SizedBox.shrink();
              return _StrandedKraNotice(names: stranded);
            }(),
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
                  now: clock ?? DateTime.now(),
                  // The grid decides both cell openness and WHICH COLUMNS
                  // EXIST, so the flow has to reach it or it draws three
                  // Self columns nobody can ever fill.
                  reviewFlow: flow,
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
            // The manager's submit sits above the rework bar: approving is the
            // common path, handing it back the exception.
            if (onSubmitManagerReview != null) ...[
              const SizedBox(height: 14),
              _ManagerSubmitBar(onSubmit: onSubmitManagerReview!),
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
              showSelfAverage: stageIsInFlow(ReviewStage.selfRating, flow),
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

/// "These KRAs have nobody to rate them."
///
/// Raised when a KRA is assigned to a reviewer the active flow does not use —
/// in practice, a KRA still pointing at the Reporting Manager on an
/// administrators-only organisation. The row cannot be scored by anyone, and
/// the server's per-KRA reviewer guard would silently discard a score entered
/// against a different seat, so an unexplained dead row is the worst possible
/// presentation: it looks like a permissions problem and is actually a
/// configuration one.
///
/// Names the KRAs and says who can fix it, because the fix is a reassignment in
/// the KRA assignment screen, not anything the rater can do from here.
class _StrandedKraNotice extends StatelessWidget {
  final List<String> names;
  const _StrandedKraNotice({required this.names});

  @override
  Widget build(BuildContext context) {
    final plural = names.length > 1;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.person_off_rounded,
              size: 15, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plural
                      ? '${names.length} KRAs have no reviewer in this flow'
                      : 'This KRA has no reviewer in this flow',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  '${names.join(', ')} — assigned to the Reporting Manager, '
                  'which this flow does not use. ${plural ? 'They' : 'It'} '
                  'cannot be rated by anyone until HR reassigns '
                  '${plural ? 'them' : 'it'} to HR or Accounts in the KRA '
                  'assignment.',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Names the review pipeline this sheet is running.
///
/// Deliberately always visible. Which flow is in effect is decided three
/// layers away — an organisation column, the login payload, the review scope —
/// and when that plumbing broke there was no way to tell from the screen. The
/// sheet sat there refusing ratings and looking perfectly normal. A viewer who
/// can read "Standard flow" on an organisation they switched to
/// administrators-only knows immediately that the setting never arrived, which
/// is a completely different problem from not having permission.
class _FlowBadge extends StatelessWidget {
  final ReviewFlow flow;
  const _FlowBadge({required this.flow});

  @override
  Widget build(BuildContext context) {
    final isStandard = flow == ReviewFlow.standard;
    // The standard flow is the overwhelmingly common case, so it is stated
    // quietly; a non-default pipeline is worth actually noticing.
    final color = isStandard ? AppColors.textMuted : AppColors.primaryPurple;
    return Tooltip(
      message: flow.description,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isStandard ? 0.06 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isStandard ? Icons.route_rounded : Icons.admin_panel_settings,
              size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            flow.displayName,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.2),
          ),
        ]),
      ),
    );
  }
}

/// A compact key explaining the per-KRA reviewer colours and the pending
/// status, so the single-reviewer model reads clearly at the top of the sheet.
class _ReviewerLegend extends StatelessWidget {
  /// Which pipeline is running, so the key does not advertise a reviewer the
  /// flow has removed. Under administrators-only there is no reporting-manager
  /// rating, and listing "Manager" there sent people looking for a column that
  /// cannot be filled by anyone.
  final ReviewFlow flow;
  const _ReviewerLegend({this.flow = ReviewFlow.standard});

  @override
  Widget build(BuildContext context) {
    // Derived from the flow rather than a hand-written list per flow — the same
    // reason actorRolesFor defers to the stage instead of restating its roles.
    final reviewers = [
      for (final r in KraReviewer.values)
        if (stageIsInFlow(stageForReviewer(r), flow)) r,
    ];
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
        for (final r in reviewers) _dot(r),
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
      Text(reviewerShortLabelFor(r, flow),
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

class _Grid extends StatefulWidget {
  /// The organisation's review pipeline. Needed here because cell openness
  /// depends on it: a flow without a self-rating must not wait for one.
  final ReviewFlow reviewFlow;

  /// See [_Sheet.clock] — the sheet resolves it once and passes it down.
  final DateTime now;
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
    required this.reviewFlow,
    required this.now,
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

  /// Whether the sheet draws its Self columns at all.
  ///
  /// Derived from the flow rather than named per flow: a pipeline with no
  /// self-rating stage never collects a self score, so those three month
  /// columns and the Qtr Self column are a dash in every row and a 0% in
  /// the totals. Under administrators-only that is exactly the state — the
  /// employee does not rate — and three dead columns pushed the two live
  /// ones off the right edge of the screen.
  bool get _showSelf =>
      stageIsInFlow(ReviewStage.selfRating, widget.reviewFlow);

  // Per month: Self | Review | Mgmt. Quarter: Self | Review | Final. Each
  // loses its Self column where the flow has no self-rating.
  int get _colsPerMonth => _showSelf ? 3 : 2;
  int get _qtrCols => _showSelf ? 3 : 2;

  // Must agree with the header, main-row and totals builders. Hide a
  // column in one of them and keep counting its width here and the sheet
  // scrolls past its own content; the reverse clips the last column.
  double get _totalWidth =>
      _wWt +
      _wKra +
      _wTgt +
      _wTrk +
      _wMon * 3 * _colsPerMonth +
      _wQtr * _qtrCols;

  String _fmt(double? p) => p == null ? '—' : '${p.round()}%';

  /// The canonical row (from the sheet's row list) carrying [rowId].
  MonthlyKraRow? _canonicalRow(String rowId) {
    for (final row in widget.rows) {
      if ((row as MonthlyKraRow).id == rowId) return row;
    }
    return null;
  }

  /// Locate the row for the same KRA within a specific month's review — each
  /// month carries its own scores AND the row's reviewer assignment.
  ///
  /// Matching by id alone was WRONG, and quietly so. The backend mints row ids
  /// with `randomUUID()` per row PER REVIEW, so the same KRA has a different id
  /// every month — while the sheet takes its canonical row list from the first
  /// month present. Every lookup for the other two months therefore missed, and
  /// the second and third columns of the quarter rendered blank no matter what
  /// anyone had entered. It reads exactly like "that month has not started".
  ///
  /// So: id first (cheap, and right when a caller already holds the month's own
  /// row), then display order — the backend's OWN join key, `display_order =
  /// sort_order` — then the normalised name, for a review generated before the
  /// orders lined up.
  MonthlyKraRow? _rowIn(MonthlyReview? r, String rowId) {
    if (r == null) return null;
    for (final row in r.rows) {
      if (row.id == rowId) return row;
    }
    final canonical = _canonicalRow(rowId);
    if (canonical == null) return null;
    for (final row in r.rows) {
      if (row.displayOrder == canonical.displayOrder) return row;
    }
    final key = kraNameKey(canonical.name);
    for (final row in r.rows) {
      if (kraNameKey(row.name) == key) return row;
    }
    return null;
  }

  /// The id to use for one KRA in one month: that month's own row id, falling
  /// back to the canonical one when the month has no matching row.
  ///
  /// Every per-month callback — the score lookup, the editor, the proof-file
  /// lookup — is keyed by row id, so they all have to be handed the id that
  /// exists in THAT month's review. Passing the canonical id made reads miss;
  /// it would also have aimed a save at a row id the month does not contain.
  String _monthRowId(int monthIdx, String rowId) =>
      _rowIn(widget.reviews[monthIdx], rowId)?.id ?? rowId;

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
  // SELF evidence where the flow HAS a self-rating, plus the assigned
  // reviewer's (RM/HR/Accounts). On the standard flow a legacy unassigned row
  // keeps just the employee slot.
  List<ReviewStage> _evidenceStages(MonthlyKraRow? row) {
    // Only the stages this flow actually has. A self remark left behind by
    // an organisation that later moved to administrators-only would
    // otherwise light the "justified" dot with evidence no longer shown.
    final stages = <ReviewStage>[if (_showSelf) ReviewStage.selfRating];
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

  /// True when [m] is the calendar month we are actually in.
  ///
  /// Drives the "this is the month that is due" emphasis in the header.
  Widget _headerRow() {
    final h = TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: AppColors.textMuted,
        height: 1.15);
    // Current month: brand-coloured instead of muted, so the column that needs
    // filling in reads differently from the two that do not.
    final hNow = h.copyWith(color: AppColors.primaryPurple);
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
        // The current month is called out, because the sheet spans a whole
        // quarter and its FIRST Self column is the quarter's first month — so
        // someone opening this to "do my self-rating" can easily fill in the
        // wrong month, believe they are done, and still be shown as overdue.
        for (final m in widget.months) ...[
          if (_showSelf)
            _cell(
                _wMon,
                Text('${m.shortLabel}\nSelf',
                    style: _isOpenReviewMonth(m, widget.now) ? hNow : h,
                    textAlign: TextAlign.right)),
          _cell(
              _wMon,
              Text('${m.shortLabel}\nReview',
                  style: _isOpenReviewMonth(m, widget.now) ? hNow : h,
                  textAlign: TextAlign.right)),
          _cell(
              _wMon,
              Text('${m.shortLabel}\nMgmt',
                  style: _isOpenReviewMonth(m, widget.now) ? hNow : h,
                  textAlign: TextAlign.right)),
        ],
        if (_showSelf)
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
    //
    // The extractor takes the MONTH INDEX, not just the review, because every
    // per-row lookup has to be keyed by that month's own row id — ids differ
    // per month (see [_rowIn]). Passing the canonical id here averaged the
    // first month against two zeroes and quietly under-reported the quarter for
    // every employee: a KRA scored 60 in all three months read as 20%.
    double qAvgRow(double? Function(int monthIdx) f) {
      double sum = 0;
      for (var i = 0; i < 3; i++) {
        sum += f(i) ?? 0;
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
        if (_showSelf)
          _cell(
              _wMon,
              _scoreCell(i, rowId, maxScore, name, ReviewStage.selfRating,
                  canEdit: (r) =>
                      widget.canEditSelf(r) &&
                      _open(i, row, ReviewStage.selfRating))),
        _cell(_wMon, _reviewCell(i, row)),
        _cell(
            _wMon,
            _scoreCell(i, rowId, maxScore, name, ReviewStage.managementReview,
                canEdit: (r) =>
                    widget.canEditManagement(r) &&
                    // Per-ROW, unlike the three gates around it. Under
                    // administrators-only, management rates the leftover KRAs
                    // and must not overwrite HR's or Accounts' own scores.
                    managementMayScoreRow(
                        row as MonthlyKraRow, widget.reviewFlow) &&
                    !r.isManagementLocked &&
                    _open(i, row, ReviewStage.managementReview))),
      ],
      if (_showSelf)
        _cell(
            _wQtr,
            Text(
                _fmt(qAvgRow((i) => widget.pct(widget.reviews[i],
                    _monthRowId(i, rowId), ReviewStage.selfRating))),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12))),
      _cell(
          _wQtr,
          Text(_fmt(qAvgRow((i) => _reviewPct(widget.reviews[i], rowId))),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
      _cell(
          _wQtr,
          Text(_fmt(qAvgRow((i) => _rowFinalPct(widget.reviews[i], rowId))),
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

  Widget _scoreCell(int monthIdx, String canonicalRowId, double maxScore,
      String name, ReviewStage stage,
      {required bool Function(MonthlyReview) canEdit}) {
    final review = widget.reviews[monthIdx];
    final rowId = _monthRowId(monthIdx, canonicalRowId);
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
            child: Text(
                'Reviewed by ${reviewerShortLabelFor(reviewer, widget.reviewFlow)}',
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

  /// Whether the (row, month, stage) cell is open for entry — see
  /// [isCellOpenForEntry]. Combined with the viewer gates, never instead of
  /// them.
  bool _open(int monthIdx, dynamic row, ReviewStage stage) {
    // The MONTH's own row — the canonical one carries the first month's self
    // score, which would open August off the back of July's rating.
    final monthRow =
        _rowIn(widget.reviews[monthIdx], (row as MonthlyKraRow).id);
    if (monthRow == null) return false;
    return isCellOpenForEntry(
      stage: stage,
      row: monthRow,
      month: widget.months[monthIdx],
      now: widget.now,
      flow: widget.reviewFlow,
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
    final rowId = _monthRowId(monthIdx, row.id as String);
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
    final open = _open(monthIdx, row, stage);
    final editable = _canEditReviewerStage(review, stage) && open;
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

    // Not open yet — so the reviewer owes nothing and must not be shown as
    // holding it up. A future month shows nothing at all; a started month
    // still waiting on the employee says so.
    if (!open) {
      if (isNotYetRatableMonth(widget.months[monthIdx], widget.now)) {
        return Text(_fmt(null),
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: AppColors.textSecondary));
      }
      return _pendingTag(AppStrings.quarterlyAwaitingSelfTag);
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
  Widget _pendingChip(KraReviewer reviewer) =>
      _pendingTag(reviewerCellTagFor(reviewer, widget.reviewFlow));

  Widget _pendingTag(String tag) {
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
          child: Text(tag,
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
                    '${_showSelf ? 'employee + reviewer' : 'reviewer'} '
                    'evidence · one per month · reason ≤ 300 chars',
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
            // No employee slot on a flow without a self-rating: nobody can
            // ever fill it, so it read "No entry" in all three months for
            // the life of the quarter.
            if (_showSelf)
              _evidenceTile(review, rowId, name, label, ReviewStage.selfRating,
                  'Employee', Icons.person_rounded, widget.canEditSelf(review)),
            if (rs != null) ...[
              // Min gap + a Spacer pins the reviewer tile to the card's bottom;
              // since the row's cards share a height, the reviewer tiles line
              // up across all three months regardless of the employee entry.
              if (_showSelf) const SizedBox(height: 8),
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
          if (_showSelf)
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
        if (_showSelf)
          _cell(
              _wQtr,
              Text('${widget.qAvg(ReviewStage.selfRating).round()}%',
                  style: t)),
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

  /// Whether to print the self average at all. A flow without a
  /// self-rating never collects one, so the line reads a flat 0% beside a
  /// real final average — which looks like the employee scored zero rather
  /// than like the row does not apply to them.
  final bool showSelfAverage;
  final double qFinal;
  final double eligibleMonthly;
  final double quarterEligible;
  final double payout;
  const _PayoutCard({
    required this.qSelf,
    required this.showSelfAverage,
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
          if (showSelfAverage)
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
                  style:
                      TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
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
/// The reporting manager's "I'm done" bar — their counterpart to
/// [_SubmitSelfRatingBar].
///
/// Same shape and placement as the employee's on purpose: the manager already
/// recognises this bar from rating their own KRAs, and the action it performs is
/// the same kind of finalisation. It only ever covers the KRAs assigned to this
/// manager; HR and Accounts submit their own stages.
class _ManagerSubmitBar extends StatefulWidget {
  final Future<void> Function() onSubmit;
  const _ManagerSubmitBar({required this.onSubmit});

  @override
  State<_ManagerSubmitBar> createState() => _ManagerSubmitBarState();
}

class _ManagerSubmitBarState extends State<_ManagerSubmitBar> {
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
                  AppStrings.mgrSubmitHint,
                  style:
                      TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
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
              AppStrings.mgrSubmitAction,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

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
        border:
            Border.all(color: AppColors.accentOrange.withValues(alpha: 0.4)),
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
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
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
            color: enabled ? AppColors.primaryPurpleLight : AppColors.textMuted,
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
      // Bytes, not a path: a browser never exposes a filesystem path, so
      // `PlatformFile.path` is ALWAYS null on web — an earlier
      // `if (path == null) return;` meant picking a file silently did nothing
      // there. Bytes are the portable representation and are what the upload
      // needs anyway.
      //
      // Read via `readAsBytes()` rather than the old `withData: true` +
      // `f.bytes`: that flag is deprecated in file_picker 12, and reading on
      // demand means a file the user then cancels out of is never loaded into
      // memory at all.
      //
      // Any file type — Excel, Word, PowerPoint, images, PDF, whatever the
      // employee's evidence happens to be. Restricting extensions just blocked
      // legitimate proof; the size cap below is the real guard.
      final f = await FilePicker.pickFile(type: FileType.any);
      if (f == null) return; // user cancelled — normal
      final bytes = await f.readAsBytes();
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

/// Whether [scope] may enter the Review score for a ROLE-GATED stage — the HR
/// rater and the Accounts rater. (The reporting-manager rater is a
/// relationship, not a role, and is gated separately.)
///
/// Resolved through [ReviewStage.actorRoles] against the caller's FULL role
/// set, so this gate cannot disagree with the badges, chips and "needs your
/// action" counts — which already resolve through `actorRoles`. It did disagree:
/// this used to test `scope.role == UserRole.finance` while
/// `financeRating.actorRoles` is `{finance, hrAdmin}`, so moving a KRA to
/// Accounts left it ratable by nobody unless someone held the literal FINANCE
/// role — the HR-admin who covers the Accounts seat was told the KRA needed
/// their action and then handed a read-only cell.
///
/// Also reads the whole role set rather than the primary role, so someone
/// holding two seats (HR *and* Accounts) can act on either.
@visibleForTesting
bool canRateReviewStage(
  ReviewStage stage,
  ReviewScope? scope,
  MonthlyReview review,
) {
  if (scope == null || review.isComplete) return false;
  // Flow-aware. For ReviewFlow.standard this is a pass-through to
  // stage.actorRoles, so the original pipeline is unchanged; for admin-only it
  // returns an empty set for the stages that flow removes, which reads as
  // "nobody can act here".
  return canActOnStage(stage, scope.reviewFlow, scope.effectiveRoles);
}

/// The [ReviewStage] a KRA's assigned reviewer group rates at.
///
/// Mirrors [MonthlyKraRow.reviewStage] but takes the group directly, so the
/// reviewer map can be checked against a flow before it is written onto a row.
@visibleForTesting
ReviewStage stageForReviewer(KraReviewer reviewer) {
  switch (reviewer) {
    case KraReviewer.reportingManager:
      return ReviewStage.reportingManagerRating;
    case KraReviewer.hr:
      return ReviewStage.accountHrRating;
    case KraReviewer.accounts:
      return ReviewStage.financeRating;
  }
}

/// The reviewer an unassigned KRA falls back to under [flow].
///
/// The reporting manager on the standard pipeline, which is the historical
/// default and stays exactly that. Any flow that removes the manager rating
/// falls back to HR instead — leaving it on the manager would produce rows no
/// role in the flow can rate.
@visibleForTesting
KraReviewer defaultReviewerFor(ReviewFlow flow) =>
    stageIsInFlow(ReviewStage.reportingManagerRating, flow)
        ? KraReviewer.reportingManager
        : KraReviewer.hr;

/// The reviewer's on-screen name under [flow].
///
/// [KraReviewer.reportingManager] is the seat that MOVES between pipelines: the
/// employee's own reporting manager on the standard flow, MANAGEMENT under
/// administrators-only. Printing "Manager" in the second case names the wrong
/// person entirely and sends the reader looking for a rating their line manager
/// is not being asked for.
///
/// Keyed off [stageIsRelationshipGated] rather than off the flow by name, so
/// the label follows whoever actually holds the seat.
@visibleForTesting
String reviewerShortLabelFor(KraReviewer reviewer, ReviewFlow flow) =>
    _seatIsManagements(reviewer, flow) ? 'Management' : reviewer.shortLabel;

/// The same seat, in the ultra-compact form the per-month cell has room for.
@visibleForTesting
String reviewerCellTagFor(KraReviewer reviewer, ReviewFlow flow) =>
    _seatIsManagements(reviewer, flow) ? 'Mgmt' : reviewer.cellTag;

bool _seatIsManagements(KraReviewer reviewer, ReviewFlow flow) =>
    reviewer == KraReviewer.reportingManager &&
    !stageIsRelationshipGated(ReviewStage.reportingManagerRating, flow);

/// Whether MANAGEMENT may enter a per-KRA score in the Mgmt column for [row].
///
/// The two flows mean different things by that column:
///
///  * [ReviewFlow.standard] — management holds no Review seat of its own. The
///    Mgmt column is the sign-off's OVERRIDE: on rework it may correct any
///    KRA's score, whoever rated it. So every row is open, exactly as before.
///
///  * [ReviewFlow.adminOnly] — management is a RATER, of the KRAs left over
///    once HR and Accounts have taken theirs. Its column is therefore its own
///    seat, not authority over everyone else's: only HR scores the HR KRA, only
///    Accounts scores the Accounts KRA. Without this, management got an
///    editable Mgmt cell on every row and could overwrite both.
///
/// A row with no assigned reviewer counts as management's, matching
/// [defaultReviewerFor] — the remainder includes the never-assigned.
///
/// This is a CLIENT restriction and cannot be enforced server-side as it
/// stands: "Save & Lock" legitimately writes a MANAGEMENT_REVIEW score for
/// every KRA (copying each Review score in so the incentive has something to
/// settle to), and the API cannot tell that bulk settle apart from a manual
/// per-cell override — both are the same `save-scores` call. Refusing the
/// stage per row would break the sign-off itself.
@visibleForTesting
bool managementMayScoreRow(MonthlyKraRow row, ReviewFlow flow) {
  if (stageIsRelationshipGated(ReviewStage.reportingManagerRating, flow)) {
    return true;
  }
  final assigned = row.reviewStage ?? ReviewStage.reportingManagerRating;
  return assigned == ReviewStage.reportingManagerRating;
}

/// KRA names whose ASSIGNED reviewer is a seat [flow] does not use.
///
/// These are stranded: no role in the flow may score them, and the server would
/// silently discard a score entered against any other seat (see the per-KRA
/// reviewer guard quoted in `_applyReviewerMap`). The only real fix is to
/// reassign the KRA, so the sheet names them rather than pretending.
///
/// Always empty on [ReviewFlow.standard] — that pipeline uses every seat — so
/// nothing about the original flow changes.
///
/// Returns names, not rows: the same KRA recurs in all three months of the
/// quarter and the reader only needs to be told once.
@visibleForTesting
List<String> kraNamesWithoutRaterInFlow(
  List<MonthlyReview?> reviews,
  ReviewFlow flow,
) {
  final names = <String>[];
  final seen = <String>{};
  for (final review in reviews) {
    if (review == null) continue;
    for (final row in review.rows) {
      final reviewer = row.reviewerGroup;
      // Unassigned: the server's per-KRA guard passes any stage for a row whose
      // reviewer_group is NULL, so there is nothing stranded to report.
      if (reviewer == null) {
        continue;
      }
      if (stageIsInFlow(stageForReviewer(reviewer), flow)) continue;
      if (seen.add(kraNameKey(row.name))) names.add(row.name);
    }
  }
  return names;
}

/// Whether [m] cannot be rated yet as of [now] — because it has not ENDED.
///
/// This replaced `isFutureMonth`, whose name was the bug. It tested "has this
/// month not STARTED", which lets the CURRENT calendar month through: on
/// 9 September the September Self cell was open, editable, and
/// `saveStageScores` persisted a rating for a month with twenty days still to
/// run. The name read as already-satisfied to anyone scanning it, which is how
/// it survived several passes over this same file.
///
/// Delegates to [ReviewPeriod.isRatableOn] so there is exactly one definition
/// of "ratable" and this cannot drift from the banner, the card or the picker.
bool isNotYetRatableMonth(ReviewPeriod m, DateTime now) => !m.isRatableOn(now);

/// Whether one cell is OPEN for entry yet — independently of WHO is looking.
///
/// The edit gates answer "are you the right person?". This answers "is there
/// anything to do yet?", and both must hold. Two rules:
///
///   * A month that has not ENDED has nothing to rate. The sheet always shows
///     a whole quarter, so through August it renders September — and September
///     was offering a live, writable Self cell for a month still in progress.
///     "Not started" was the old test, and it let the current month through.
///   * Everything downstream of the self-rating needs that self-rating to
///     exist, PER KRA. A reviewer rating first inverts the pipeline: their
///     score is meant to moderate the employee's, and the reporting manager is
///     explicitly capped by it, so rating first would set the ceiling for a
///     number the employee has not chosen yet.
///
/// Deliberately per KRA rather than per month: each KRA is rated on its own
/// row, so one unrated KRA should not close the ones the employee has done.
@visibleForTesting
bool isCellOpenForEntry({
  required ReviewStage stage,
  required MonthlyKraRow row,
  required ReviewPeriod month,
  required DateTime now,
  ReviewFlow flow = ReviewFlow.standard,
}) {
  if (isNotYetRatableMonth(month, now)) return false;
  if (stage == ReviewStage.selfRating) return true;

  // The self-first ordering only means anything in a flow that HAS a
  // self-rating. Under a flow without one there is no score to wait for and
  // none will ever arrive, so keeping the prerequisite closed every cell in
  // the sheet for every rater — HR, Accounts and management included. That
  // was not a narrow bug: the entire pipeline was unusable.
  //
  // Defaults to standard, so every existing caller and test is unaffected.
  if (!stageIsInFlow(ReviewStage.selfRating, flow)) return true;

  return row.scoreFor(ReviewStage.selfRating)?.value != null;
}

/// The month in this quarter that is the CURRENT calendar month and still has
/// no self score, or null when there is nothing outstanding.
///
/// Only ever the current month: an untouched earlier month is water under the
/// bridge, and nagging about it would bury the one that actually matters.
ReviewPeriod? _currentMonthNeedingSelfRating(
    List<ReviewPeriod> months, List<MonthlyReview?> reviews, DateTime now) {
  for (var i = 0; i < months.length && i < reviews.length; i++) {
    final month = months[i];
    if (!_isOpenReviewMonth(month, now)) continue;
    final review = reviews[i];
    if (review == null) return month; // not generated yet — still outstanding
    final rated = review.rows
        .any((r) => r.scoreFor(ReviewStage.selfRating)?.value != null);
    return rated ? null : month;
  }
  return null;
}

/// Whether [m] is the month whose rating window is open as of [now].
///
/// NOT "is this today's calendar month". Today's month has not ended, so
/// nothing in it can be rated yet; the month that matters to a rater is the
/// previous one. Used both to highlight the live column in the header and to
/// find the month still owing a self-rating.
bool _isOpenReviewMonth(ReviewPeriod m, DateTime now) =>
    m.key == ReviewPeriod.openForRating(now).key;
