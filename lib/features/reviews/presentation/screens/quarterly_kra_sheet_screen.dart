import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_gradients.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/adaptive_leading.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/workspace_drawer.dart';
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/review_stage.dart';
import '../../data/models/row_score.dart';
import '../../data/repositories/monthly_review_repository.dart';
import '../providers/monthly_review_providers.dart';

const _monthAbbr = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
        isSelf: stage == ReviewStage.selfRating,
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
  Future<void> _openProofFile(MonthlyReview review, String rowId) async {
    setState(() => _saving = true);
    try {
      final file = await ref
          .read(monthlyReviewRepositoryProvider)
          .fetchProofFile(review.id, rowId, ReviewStage.selfRating);
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

  /// The per-KRA, per-MONTH "Reason & Proof" line item. The review runs monthly,
  /// so each month ([review]) captures its own reason (max 300 chars) + one proof
  /// attachment. The EMPLOYEE (owner of the sheet) fills it in for their KRAs;
  /// the reporting manager / HR / admin can only VIEW it (they never upload proof
  /// for their own rating). Both the reason (remark) and the attachment now
  /// persist on that month's SELF_RATING score, so the reporting manager and
  /// management see exactly the evidence the employee filed.
  Future<void> _openJustification({
    required MonthlyReview review,
    required String rowId,
    required String kraName,
    required String monthLabel,
    required bool canEdit,
  }) async {
    final current = _currentScore(review, rowId, ReviewStage.selfRating);
    final key = '${review.id}|$rowId';
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
              ? () => _openProofFile(review, rowId)
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
      // Preserve this month's existing self score — the reason rides alongside it.
      await ref.read(monthlyReviewRepositoryProvider).saveStageScores(
        review.id,
        ReviewStage.selfRating,
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
          reviews: data.reviews,
          scope: scope,
          onPrevQuarter: () => setState(() => _anchor =
              quarterMonthsFor(_anchor!).first.let((m) => _shiftQuarter(m, -1))),
          onNextQuarter: () => setState(() => _anchor =
              quarterMonthsFor(_anchor!).first.let((m) => _shiftQuarter(m, 1))),
          pct: _pct,
          canEditSelf: (r) => _canEditSelf(r, scope),
          canEditManager: (r) => _canEditManager(r, scope),
          onEdit: _editCell,
          onJustify: _openJustification,
          // Server value first: a reporting manager / management never picked
          // the file, so only the stored name can tell them evidence exists.
          // The local pick is just an optimistic echo for the uploader.
          fileNameFor: (review, rowId) =>
              _currentScore(review, rowId, ReviewStage.selfRating)
                  ?.proofFileName ??
              _proofFiles['${review.id}|$rowId']?.name,
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
      required kraName,
      required monthLabel,
      required canEdit,
    }) async {},
    fileNameFor: (_, __) => null,
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
    required String kraName,
    required String monthLabel,
    required bool canEdit,
  }) onJustify;
  final String? Function(MonthlyReview, String) fileNameFor;

  const _Sheet({
    required this.months,
    required this.reviews,
    required this.scope,
    required this.onPrevQuarter,
    required this.onNextQuarter,
    required this.pct,
    required this.canEditSelf,
    required this.canEditManager,
    required this.onEdit,
    required this.onJustify,
    required this.fileNameFor,
  });

  MonthlyReview? get _any => reviews.firstWhere((r) => r != null, orElse: () => null);

  @override
  Widget build(BuildContext context) {
    final any = _any;
    if (any == null) {
      // A review row only exists once HR has generated the cycle's monthly
      // reviews. Employees added mid-cycle land here until that happens, so
      // explain it rather than dead-ending on a bare "no review" line.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_note_outlined,
                  size: 44, color: AppColors.textMuted),
              SizedBox(height: 14),
              Text(
                'No review to rate yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 8),
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
    final rows = [...any.rows]..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    // Weighted monthly totals per stage (0–100) and the quarter average.
    double monthTotal(int i, ReviewStage stage) =>
        reviews[i]?.weightedScorePct(stage) ?? 0;
    double qAvg(ReviewStage stage) =>
        (monthTotal(0, stage) + monthTotal(1, stage) + monthTotal(2, stage)) / 3;

    final canSelf = canEditSelf(any);
    final canMgr = canEditManager(any);
    final scopeLabel = canSelf
        ? 'You can edit the Self ratings on this sheet.'
        : canMgr
            ? 'You can edit the Manager ratings for your report.'
            : 'View only — you cannot edit this sheet.';

    final qMgr = qAvg(ReviewStage.reportingManagerRating);
    final qSelf = qAvg(ReviewStage.selfRating);
    final eligibleMonthly = any.eligibleAmount;
    final quarterEligible = eligibleMonthly * 3;
    final payout = quarterEligible * qMgr / 100;

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _HeaderCard(
          review: any,
          months: months,
          onPrev: onPrevQuarter,
          onNext: onNextQuarter,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Icon(canSelf || canMgr ? Icons.edit_rounded : Icons.visibility_rounded,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(scopeLabel,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _Grid(
            rows: rows,
            months: months,
            reviews: reviews,
            pct: pct,
            canEditSelf: canEditSelf,
            canEditManager: canEditManager,
            onEdit: onEdit,
            onJustify: onJustify,
            fileNameFor: fileNameFor,
            monthTotal: monthTotal,
            qAvg: qAvg,
          ),
        ),
        const SizedBox(height: 16),
        _PayoutCard(
          qSelf: qSelf,
          qMgr: qMgr,
          eligibleMonthly: eligibleMonthly,
          quarterEligible: quarterEligible,
          payout: payout,
        ),
      ],
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

class _Grid extends StatefulWidget {
  final List<dynamic> rows; // MonthlyKraRow
  final List<ReviewPeriod> months;
  final List<MonthlyReview?> reviews;
  final double? Function(MonthlyReview?, String, ReviewStage) pct;
  final bool Function(MonthlyReview) canEditSelf;
  final bool Function(MonthlyReview) canEditManager;
  final Future<void> Function({
    required MonthlyReview review,
    required String rowId,
    required double maxScore,
    required ReviewStage stage,
    required double? currentPct,
    required String kraName,
    required String monthLabel,
  }) onEdit;
  // The Reason & Proof line item is per KRA AND per month — it opens the
  // matching month's review, not a single quarter anchor.
  final Future<void> Function({
    required MonthlyReview review,
    required String rowId,
    required String kraName,
    required String monthLabel,
    required bool canEdit,
  }) onJustify;
  final String? Function(MonthlyReview, String) fileNameFor;
  final double Function(int, ReviewStage) monthTotal;
  final double Function(ReviewStage) qAvg;

  const _Grid({
    required this.rows,
    required this.months,
    required this.reviews,
    required this.pct,
    required this.canEditSelf,
    required this.canEditManager,
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
      _wMon = 68,
      _wQtr = 54;
  double get _totalWidth =>
      _wWt + _wKra + _wTgt + _wTrk + _wMon * 6 + _wQtr * 2;

  String _fmt(double? p) => p == null ? '—' : '${p.round()}%';

  RowScore? _selfScore(MonthlyReview r, String rowId) {
    for (final row in r.rows) {
      if (row.id == rowId) return row.scoreFor(ReviewStage.selfRating);
    }
    return null;
  }

  // A KRA is "justified" if ANY of its months has a reason or an attachment.
  bool _anyJustified(String rowId) {
    for (final r in widget.reviews) {
      if (r == null) continue;
      final s = _selfScore(r, rowId);
      if (s?.remark?.trim().isNotEmpty ?? false) return true;
      if (widget.fileNameFor(r, rowId) != null) return true;
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
    const h = TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: AppColors.textMuted,
        height: 1.15);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(children: [
        _cell(_wWt, const Text('Wt', style: h), align: Alignment.centerLeft),
        _cell(_wKra, const Text('KRA', style: h), align: Alignment.centerLeft),
        _cell(_wTgt, const Text('Target', style: h),
            align: Alignment.centerLeft),
        _cell(_wTrk, const Text('Tracking\nmethod', style: h),
            align: Alignment.centerLeft),
        for (final m in widget.months) ...[
          _cell(_wMon,
              Text('${_shortMonth(m)}\nSelf', style: h, textAlign: TextAlign.right)),
          _cell(_wMon,
              Text('${_shortMonth(m)}\nMgr', style: h, textAlign: TextAlign.right)),
        ],
        _cell(_wQtr, const Text('Qtr\nSelf', style: h, textAlign: TextAlign.right)),
        _cell(_wQtr, const Text('Qtr\nMgr', style: h, textAlign: TextAlign.right)),
      ]),
    );
  }

  List<Widget> _kraBlock(dynamic row) {
    final rowId = row.id as String;
    return [
      Container(
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: AppColors.divider.withValues(alpha: 0.5))),
        ),
        child: _mainRow(row),
      ),
      if (_expanded.contains(rowId))
        Container(
          width: _totalWidth,
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.035),
            border: const Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: _lineItem(row),
        ),
    ];
  }

  Widget _mainRow(dynamic row) {
    final rowId = row.id as String;
    final maxScore = (row.maxScore as num).toDouble();
    final name = row.name as String;
    double qKra(ReviewStage stage) {
      final vals = [
        for (var i = 0; i < 3; i++)
          widget.pct(widget.reviews[i], rowId, stage) ?? 0,
      ];
      return (vals[0] + vals[1] + vals[2]) / 3;
    }

    return Row(children: [
      _cell(_wWt, Text('${(row.weightagePercent as num).round()}%',
          style: const TextStyle(fontSize: 12)), align: Alignment.centerLeft),
      _cell(_wKra, _kraNameBlock(row), align: Alignment.centerLeft),
      _cell(_wTgt, _targetCell(row), align: Alignment.centerLeft),
      _cell(_wTrk, _trackingCell(row), align: Alignment.centerLeft),
      for (var i = 0; i < 3; i++) ...[
        _cell(_wMon, _scoreCell(i, rowId, maxScore, name, ReviewStage.selfRating)),
        _cell(_wMon,
            _scoreCell(i, rowId, maxScore, name, ReviewStage.reportingManagerRating)),
      ],
      _cell(_wQtr, Text(_fmt(qKra(ReviewStage.selfRating)),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
      _cell(_wQtr, Text(_fmt(qKra(ReviewStage.reportingManagerRating)),
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
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
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
              Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 14, color: color),
              const SizedBox(width: 3),
              Flexible(
                child: Text('Reason & proof',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
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
      return const Text('—',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted));
    }
    return Text(target.trim(),
        style: const TextStyle(
            fontSize: 11.5,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary));
  }

  // Tracking method in its own column — shown in full (no truncation).
  Widget _trackingCell(dynamic row) {
    final tracking = row.trackingMethod as String?;
    if (tracking == null || tracking.trim().isEmpty) {
      return const Text('—',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted));
    }
    return Text(tracking.trim(),
        style: const TextStyle(
            fontSize: 11, height: 1.3, color: AppColors.textMuted));
  }

  Widget _scoreCell(int monthIdx, String rowId, double maxScore, String name,
      ReviewStage stage) {
    final review = widget.reviews[monthIdx];
    final p = widget.pct(review, rowId, stage);
    final editable = review != null &&
        (stage == ReviewStage.selfRating
            ? widget.canEditSelf(review)
            : widget.canEditManager(review));
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

  // The full-width expandable Reason & Proof line item — one entry per month.
  Widget _lineItem(dynamic row) {
    final rowId = row.id as String;
    final name = row.name as String;
    final maxW = (MediaQuery.of(context).size.width - 32).clamp(300.0, 560.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_wWt + 6, 10, 12, 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.sticky_note_2_outlined,
                  size: 13, color: AppColors.textMuted),
              SizedBox(width: 5),
              Text('Reason & proof — one per month (reason ≤ 300 chars)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted)),
            ]),
            const SizedBox(height: 8),
            for (var i = 0; i < 3; i++) _monthReasonRow(row, i, rowId, name),
          ],
        ),
      ),
    );
  }

  Widget _monthReasonRow(dynamic row, int i, String rowId, String name) {
    final review = widget.reviews[i];
    final label = _shortMonth(widget.months[i]);
    if (review == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(
              width: 56,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted))),
          const SizedBox(width: 8),
          const Text('Not generated yet',
              style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic)),
        ]),
      );
    }
    final s = _selfScore(review, rowId);
    final reason = s?.remark?.trim() ?? '';
    final fileName = widget.fileNameFor(review, rowId);
    final canEdit = widget.canEditSelf(review);
    final filled = reason.isNotEmpty || fileName != null;
    final promptText = filled
        ? (reason.isNotEmpty ? reason : 'Attachment added')
        : (canEdit ? 'Add reason & proof' : 'No reason & proof');
    final promptColor = filled
        ? AppColors.textPrimary
        : (canEdit ? AppColors.primaryPurple : AppColors.textMuted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onJustify(
            review: review,
            rowId: rowId,
            kraName: name,
            monthLabel: label,
            canEdit: canEdit,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(children: [
              SizedBox(
                  width: 48,
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w800))),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(promptText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                filled ? FontWeight.w500 : FontWeight.w700,
                            color: promptColor)),
                    if (fileName != null) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        const Icon(Icons.attach_file_rounded,
                            size: 11, color: AppColors.primaryPurple),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.textSecondary)),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(canEdit ? Icons.edit_rounded : Icons.visibility_rounded,
                  size: 14, color: AppColors.textMuted),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _totalsRow() {
    const t = TextStyle(fontWeight: FontWeight.w800, fontSize: 12);
    return Container(
      decoration:
          BoxDecoration(color: AppColors.primaryPurple.withValues(alpha: 0.06)),
      child: Row(children: [
        _cell(_wWt,
            const Text('100%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
            align: Alignment.centerLeft),
        _cell(_wKra, const Text('Total', style: t), align: Alignment.centerLeft),
        _cell(_wTgt, const SizedBox.shrink(), align: Alignment.centerLeft),
        _cell(_wTrk, const SizedBox.shrink(), align: Alignment.centerLeft),
        for (var i = 0; i < 3; i++) ...[
          _cell(_wMon,
              Text('${widget.monthTotal(i, ReviewStage.selfRating).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
          _cell(
              _wMon,
              Text(
                  '${widget.monthTotal(i, ReviewStage.reportingManagerRating).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
        ],
        _cell(_wQtr, Text('${widget.qAvg(ReviewStage.selfRating).round()}%', style: t)),
        _cell(
            _wQtr,
            Text('${widget.qAvg(ReviewStage.reportingManagerRating).round()}%',
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
  final double qMgr;
  final double eligibleMonthly;
  final double quarterEligible;
  final double payout;
  const _PayoutCard({
    required this.qSelf,
    required this.qMgr,
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
          _row('Quarter manager average', '${qMgr.round()}%'),
          _row('Monthly incentive', EmployeeFormatters.currencyInr(eligibleMonthly)),
          _row('Quarter eligible (×3)',
              EmployeeFormatters.currencyInr(quarterEligible)),
          const Divider(height: 20),
          _row(
            AppStrings.quarterlyPayoutAmount,
            EmployeeFormatters.currencyInr(payout),
            emphasize: true,
          ),
          const SizedBox(height: 4),
          const Text(
            'Payout = monthly incentive × 3 × quarter manager average.',
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
  final bool isSelf;
  final double? currentPct;
  const _RatingSheet({
    required this.kraName,
    required this.monthLabel,
    required this.isSelf,
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
              '${widget.monthLabel} · '
              '${widget.isSelf ? 'Self rating' : 'Manager rating'}',
              style: const TextStyle(
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
              style: const TextStyle(
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
            const Text('Quick set',
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
                      side: const BorderSide(color: AppColors.divider),
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
              style: const TextStyle(
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
                style: const TextStyle(
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
            side: const BorderSide(color: AppColors.divider),
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
                  style: const TextStyle(
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
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          AppStrings.ratingProofFileLocalNote,
          style: TextStyle(
              fontSize: 10.5, color: AppColors.textMuted, height: 1.3),
        ),
      ],
    );
  }
}

/// Shows a fetched proof attachment. Images render inline; anything else (PDF)
/// is acknowledged by name — enough for the reviewer to confirm evidence exists.
class _ProofFileViewer extends StatelessWidget {
  final ProofFileDownload file;
  const _ProofFileViewer({required this.file});

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
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
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
                      style: const TextStyle(
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
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          _labelled('Reason',
              reason.trim().isEmpty ? AppStrings.ratingNoReason : reason.trim(),
              muted: reason.trim().isEmpty),
          const SizedBox(height: 12),
          const Text('PROOF ATTACHMENT',
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
                        style: const TextStyle(
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
            const Text('No attachment uploaded.',
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
            style: const TextStyle(
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
