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
import '../../data/repositories/monthly_review_repository.dart';
import '../providers/kra_reviewer_map_provider.dart';
import '../providers/monthly_review_providers.dart';

const _monthAbbr = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

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

String _shortMonth(ReviewPeriod p) =>
    "${_monthAbbr[p.month]} '${p.year.toString().substring(2)}";

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
  MonthlyReview? _applyReviewerMap(MonthlyReview? r, KraReviewerAssignment map) {
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
  bool _canEditSelf(MonthlyReview r, ReviewScope? scope) {
    if (scope == null) return false;
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
    if (scope == null) return false;
    return r.managerId != null && r.managerId == scope.userId;
  }

  // The three Review-cycle raters are entered in parallel. Two are gated by
  // ROLE (HR, Finance); the reporting-manager one stays a RELATIONSHIP (above).
  //   * HR rating       → HR / HR_ADMIN
  //   * Finance rating  → FINANCE
  bool _canEditHr(ReviewScope? scope) =>
      scope != null &&
      (scope.role == UserRole.hr || scope.role == UserRole.hrAdmin);
  bool _canEditFinance(ReviewScope? scope) =>
      scope != null && scope.role == UserRole.finance;

  // Management review (cycle 3) — HR either approves the Review average or, on
  // rework, overrides it per KRA. Done by HR_ADMIN / ADMIN.
  bool _canEditManagement(ReviewScope? scope) =>
      scope != null &&
      (scope.role == UserRole.hrAdmin || scope.role == UserRole.admin);

  Future<void> _editCell({
    required MonthlyReview review,
    required String rowId,
    required double maxScore,
    required ReviewStage stage,
    required double? currentPct,
    required String kraName,
    required String monthLabel,
  }) async {
    // Accessible rating entry: a slider + one-tap presets in a bottom sheet.
    // Tapping a preset saves immediately (no separate "edit then save" step).
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
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
        data: (data) => _Sheet(
          months: data.months,
          reviews: [
            for (final r in data.reviews) _applyReviewerMap(r, reviewerMap),
          ],
          scope: scope,
          onPrevQuarter: () => setState(() => _anchor =
              quarterMonthsFor(_anchor!)
                  .first
                  .let((m) => _shiftQuarter(m, -1))),
          onNextQuarter: () => setState(() => _anchor =
              quarterMonthsFor(_anchor!).first.let((m) => _shiftQuarter(m, 1))),
          pct: _pct,
          canEditSelf: (r) => _canEditSelf(r, scope),
          canEditManager: (r) => _canEditManager(r, scope),
          canEditHr: _canEditHr(scope),
          canEditFinance: _canEditFinance(scope),
          canEditManagement: _canEditManagement(scope),
          onEdit: _editCell,
          onJustify: _openJustification,
          // Server value first: a viewer never picked the file, so only the
          // stored name can tell them evidence exists. The local pick is just an
          // optimistic echo for whoever uploaded it. Keyed by stage so the
          // employee's and each reviewer's attachments are tracked separately.
          fileNameFor: (review, rowId, stage) =>
              _currentScore(review, rowId, stage)?.proofFileName ??
              _proofFiles['${review.id}|$rowId|${stage.name}']?.name,
        ),
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
    canEditSelf: (_) => editableSelf,
    canEditManager: (_) => editableManager,
    canEditHr: editableHr,
    canEditFinance: editableFinance,
    canEditManagement: false,
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
  final bool canEditHr;
  final bool canEditFinance;
  final bool canEditManagement;
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

    final canSelf = canEditSelf(any);
    final canMgr = canEditManager(any);
    final canEditAny =
        canSelf || canMgr || canEditHr || canEditFinance || canEditManagement;
    final scopeLabel = canSelf
        ? 'You can edit the Self ratings on this sheet.'
        : canMgr
            ? 'You can rate the KRAs assigned to you as Reporting Manager — '
                'tap a Review cell.'
            : canEditHr
                ? 'You can rate the KRAs assigned to HR — tap a Review cell.'
                : canEditFinance
                    ? 'You can rate the KRAs assigned to Accounts — '
                        'tap a Review cell.'
                    : canEditManagement
                        ? 'You can enter the Management rating for each KRA.'
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
                '${_shortMonth(months.first)} – ${_shortMonth(months.last)}',
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
  final bool canEditHr;
  final bool canEditFinance;
  final bool canEditManagement;
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
        _cell(_wTgt, Text('Target', style: h),
            align: Alignment.centerLeft),
        _cell(_wTrk, Text('Tracking\nmethod', style: h),
            align: Alignment.centerLeft),
        for (final m in widget.months) ...[
          _cell(
              _wMon,
              Text('${_shortMonth(m)}\nSelf',
                  style: h, textAlign: TextAlign.right)),
          _cell(
              _wMon,
              Text('${_shortMonth(m)}\nReview',
                  style: h, textAlign: TextAlign.right)),
          _cell(
              _wMon,
              Text('${_shortMonth(m)}\nMgmt',
                  style: h, textAlign: TextAlign.right)),
        ],
        _cell(_wQtr,
            Text('Qtr\nSelf', style: h, textAlign: TextAlign.right)),
        _cell(_wQtr,
            Text('Qtr\nReview', style: h, textAlign: TextAlign.right)),
        _cell(_wQtr,
            Text('Qtr\nFinal', style: h, textAlign: TextAlign.right)),
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
                canEdit: (_) => widget.canEditManagement)),
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
        style: TextStyle(
            fontSize: 11, height: 1.3, color: AppColors.textMuted));
  }

  Widget _scoreCell(int monthIdx, String rowId, double maxScore, String name,
      ReviewStage stage,
      {required bool Function(MonthlyReview) canEdit}) {
    final review = widget.reviews[monthIdx];
    final p = widget.pct(review, rowId, stage);
    final editable = review != null && canEdit(review);
    final text = Text(_fmt(p),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: editable ? AppColors.primaryPurple : AppColors.textSecondary,
        ));
    if (!editable) return text;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => widget.onEdit(
        review: review,
        rowId: rowId,
        maxScore: maxScore,
        stage: stage,
        currentPct: p,
        kraName: name,
        monthLabel: _shortMonth(widget.months[monthIdx]),
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
        return widget.canEditHr;
      case ReviewStage.financeRating:
        return widget.canEditFinance;
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
          monthLabel: _shortMonth(widget.months[monthIdx]),
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
                            ? _monthCard(
                                row, start + c, rowId, name, reviewer)
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
    final label = _shortMonth(widget.months[i]);
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
  const _RatingSheet({
    required this.kraName,
    required this.monthLabel,
    required this.stageLabel,
    required this.currentPct,
  });

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  late double _val;

  @override
  void initState() {
    super.initState();
    _val = (widget.currentPct ?? 0).clamp(0, 100).toDouble();
  }

  void _commit(double v) =>
      Navigator.of(context).pop(v.clamp(0, 100).toDouble());

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
                onChanged: (v) => setState(() => _val = v),
              ),
            ),
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
                  InkWell(
                    onTap: () => _commit(p.toDouble()),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.primaryPurple
                                .withValues(alpha: 0.30)),
                      ),
                      child: Text('$p%',
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryPurpleLight)),
                    ),
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
