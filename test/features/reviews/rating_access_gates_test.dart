import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_window.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/data/models/stage_record.dart';
import 'package:vistar_app/features/reviews/presentation/providers/monthly_review_providers.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The sheet's gates once the server sends rating windows
/// (docs/RATING_ACCESS.md §4.2).
///
/// A window, when present, decides WHEN on its own. None of the client's
/// reach-backs — the blank self-rating backfill, management sign-off of any
/// ended month, RatingReopen, the rework flag — are consulted: the server has
/// already folded the ones it keeps into the window, and refuses every write
/// the window does not allow. A gate that let a reach-back through would offer
/// a cell whose save then comes back 403.
///
/// The other half matters as much: with NO window — an older backend — every
/// gate behaves exactly as it did before.
void main() {
  // The server resolves every instant in IST. Noon on 2 Oct 2026: September
  // is the calendar's open month and its windows run to the 10th–15th; July
  // and August are past every deadline; October is still running.
  DateTime ist(int y, int m, int d,
          [int h = 0, int mi = 0, int s = 0, int ms = 0]) =>
      DateTime.utc(y, m, d, h, mi, s, ms)
          .subtract(const Duration(hours: 5, minutes: 30));
  final now = ist(2026, 10, 2, 12);

  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);
  const october = ReviewPeriod(2026, 10);

  // The seeded July/August reopen: end of 31 Oct, IST.
  final seedUntil = ist(2026, 10, 31, 23, 59, 59, 999);

  /// [stage]'s window for [month] as the server resolves it: open from the
  /// first of the next month, closing at its deadline unless overridden.
  RatingWindow window(
    ReviewPeriod month,
    ReviewStage stage, {
    RatingWindowSource source = RatingWindowSource.deadline,
    DateTime? closesAt,
    bool noEnd = false,
  }) {
    final n = month.next;
    final deadlineAt =
        ist(n.year, n.month, stage.publishedDeadlineDay ?? 10, 23, 59, 59, 999);
    final closed = source == RatingWindowSource.closed;
    return RatingWindow(
      source: source,
      closed: closed,
      opensAt: ist(n.year, n.month, 1),
      closesAt: closed || noEnd ? null : (closesAt ?? deadlineAt),
      deadlineAt: deadlineAt,
    );
  }

  RatingWindow opened(ReviewPeriod m, ReviewStage s) =>
      window(m, s, source: RatingWindowSource.opened, closesAt: seedUntil);
  RatingWindow forceClosed(ReviewPeriod m, ReviewStage s) =>
      window(m, s, source: RatingWindowSource.closed);
  RatingWindow returned(ReviewPeriod m) => window(m, ReviewStage.selfRating,
      source: RatingWindowSource.returned, noEnd: true);

  /// All five rating stages of [month] on their deadlines, with [overrides].
  Map<ReviewStage, RatingWindow> windows(ReviewPeriod month,
          [Map<ReviewStage, RatingWindow> overrides = const {}]) =>
      {
        for (final s in ReviewStage.values)
          if (s.isRatingStage) s: window(month, s),
        ...overrides,
      };

  MonthlyKraRow row({double? self, ReviewStage? ratedBy}) {
    var r = const MonthlyKraRow(
      id: 'k1',
      name: 'Safety of the Facility',
      weightagePercent: 100,
      maxScore: 10,
      reviewerGroup: KraReviewer.reportingManager,
      displayOrder: 1,
    );
    if (self != null) {
      r = r.withStageScore(ReviewStage.selfRating, RowScore(value: self));
    }
    if (ratedBy != null) {
      r = r.withStageScore(ratedBy, const RowScore(value: 6));
    }
    return r;
  }

  group('isCellOpenForEntry with a server window', () {
    bool open(
      ReviewStage stage,
      ReviewPeriod month,
      RatingWindow? w, {
      MonthlyKraRow? r,
      ReviewFlow flow = ReviewFlow.standard,
      bool returnedForRework = false,
      bool reopenedForBackfill = false,
    }) =>
        isCellOpenForEntry(
          stage: stage,
          row: r ?? row(self: 8),
          month: month,
          now: now,
          flow: flow,
          returnedForRework: returnedForRework,
          reopenedForBackfill: reopenedForBackfill,
          window: w,
        );

    test('a DEADLINE window still running is open to every stage', () {
      for (final s in ReviewStage.values.where((s) => s.isRatingStage)) {
        expect(open(s, september, window(september, s)), isTrue, reason: '$s');
      }
    });

    test('past its deadline it is shut — whatever the reach-backs say', () {
      // Legacy would open all three: a blank self cell (backfill), a pending
      // reviewer cell in a RatingReopen month, and management sign-off of any
      // ended month. The server would refuse each of them.
      expect(
          open(ReviewStage.selfRating, august,
              window(august, ReviewStage.selfRating),
              r: row()),
          isFalse,
          reason: 'blank self backfill is not consulted');
      expect(
          open(ReviewStage.reportingManagerRating, august,
              window(august, ReviewStage.reportingManagerRating),
              reopenedForBackfill: true),
          isFalse,
          reason: 'RatingReopen is not consulted');
      expect(
          open(ReviewStage.managementReview, august,
              window(august, ReviewStage.managementReview)),
          isFalse,
          reason: 'sign-off of any ended month is not consulted');
    });

    test('OPENED past the deadline is rate-AND-edit, unlike the old reopen',
        () {
      // RatingReopen opened only blank cells; an override opens rated ones.
      final rated = row(self: 8, ratedBy: ReviewStage.reportingManagerRating);
      expect(
          open(ReviewStage.reportingManagerRating, july,
              opened(july, ReviewStage.reportingManagerRating),
              r: rated),
          isTrue);
      expect(
          open(ReviewStage.selfRating, august,
              opened(august, ReviewStage.selfRating)),
          isTrue,
          reason: 'a self score already given can be revised too');
    });

    test('CLOSED shuts a stage inside its own deadline', () {
      expect(
          open(ReviewStage.selfRating, september,
              forceClosed(september, ReviewStage.selfRating)),
          isFalse);
      expect(
          open(ReviewStage.accountHrRating, september,
              forceClosed(september, ReviewStage.accountHrRating)),
          isFalse);
    });

    test('a RETURNED self window has no end — and opens SELF only', () {
      expect(open(ReviewStage.selfRating, july, returned(july)), isTrue);
      // The rework flag is not what opened it: the window alone does.
      expect(
          open(ReviewStage.selfRating, july, returned(july),
              returnedForRework: false),
          isTrue);
      // Each stage reads its own window, so the return reopens nothing else.
      expect(
          open(ReviewStage.reportingManagerRating, july,
              window(july, ReviewStage.reportingManagerRating),
              returnedForRework: true),
          isFalse);
    });

    test('a window can never open a month that has not ended', () {
      // Defensive: a window claiming October is open on 2 October is wrong,
      // and the month rule still refuses it.
      final bogus = RatingWindow(
        source: RatingWindowSource.opened,
        closed: false,
        opensAt: ist(2026, 9, 1),
      );
      for (final s in ReviewStage.values.where((s) => s.isRatingStage)) {
        expect(open(s, october, bogus), isFalse, reason: '$s');
      }
    });

    test('STANDARD still waits for the self-rating, per KRA', () {
      for (final s in [
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
        ReviewStage.managementReview,
      ]) {
        expect(open(s, july, opened(july, s), r: row()), isFalse,
            reason: '$s without a self score');
        expect(open(s, july, opened(july, s), r: row(self: 0)), isTrue,
            reason: '$s once self-rated — a zero counts');
      }
    });

    test('ADMIN_ONLY needs no self score', () {
      for (final s in [
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
        ReviewStage.managementReview,
      ]) {
        expect(
            open(s, september, window(september, s),
                r: row(), flow: ReviewFlow.adminOnly),
            isTrue,
            reason: '$s');
      }
    });
  });

  group('isCellOpenForEntry with no window keeps the old rule', () {
    // Outcomes the legacy rule is known to give on 2 Oct, pinned here so the
    // window branch cannot leak into it.
    bool legacy(ReviewStage stage, ReviewPeriod month, MonthlyKraRow r,
            {bool returned = false, bool reopened = false}) =>
        isCellOpenForEntry(
          stage: stage,
          row: r,
          month: month,
          now: now,
          returnedForRework: returned,
          reopenedForBackfill: reopened,
        );

    test('every reach-back still reaches back', () {
      expect(legacy(ReviewStage.selfRating, july, row()), isTrue,
          reason: 'blank self backfill');
      expect(legacy(ReviewStage.selfRating, july, row(self: 8)), isFalse);
      expect(legacy(ReviewStage.selfRating, july, row(self: 8), returned: true),
          isTrue,
          reason: 'rework return');
      expect(
          legacy(ReviewStage.reportingManagerRating, july, row(self: 8),
              reopened: true),
          isTrue,
          reason: 'RatingReopen backfill');
      expect(legacy(ReviewStage.managementReview, july, row(self: 8)), isTrue,
          reason: 'sign-off of an ended month');
    });

    test('and the calendar window still holds', () {
      expect(legacy(ReviewStage.reportingManagerRating, july, row(self: 8)),
          isFalse);
      expect(
          legacy(ReviewStage.reportingManagerRating, september, row(self: 8)),
          isTrue);
      expect(legacy(ReviewStage.selfRating, october, row()), isFalse);
    });

    test('an explicit null window is the same as none', () {
      for (final s in ReviewStage.values.where((s) => s.isRatingStage)) {
        for (final m in [july, august, september, october]) {
          for (final r in [row(), row(self: 8)]) {
            for (final (wasReturned, wasReopened) in [
              (false, false),
              (true, false),
              (false, true),
            ]) {
              expect(
                isCellOpenForEntry(
                  stage: s,
                  row: r,
                  month: m,
                  now: now,
                  returnedForRework: wasReturned,
                  reopenedForBackfill: wasReopened,
                  window: null,
                ),
                legacy(s, m, r, returned: wasReturned, reopened: wasReopened),
                reason: '$s ${m.key} returned=$wasReturned '
                    'reopened=$wasReopened',
              );
            }
          }
        }
      }
    });
  });

  group('canEditSelfRating', () {
    const owner =
        ReviewScope(userId: 'emp1', userName: 'Asha', role: UserRole.employee);
    const someoneElse =
        ReviewScope(userId: 'mgr1', userName: 'Manish', role: UserRole.manager);
    const adminOnlyOwner = ReviewScope(
        userId: 'emp1',
        userName: 'Asha',
        role: UserRole.employee,
        reviewFlow: ReviewFlow.adminOnly);

    StageRecord returnRecord() => StageRecord(
          actorId: 'mgr1',
          actorName: 'Manish',
          submittedAt: ist(2026, 9, 20),
          comment: 'Revisit the safety KRA',
          returned: true,
        );

    MonthlyReview review(
      ReviewPeriod period, {
      MonthlyKraRow? r,
      Map<ReviewStage, RatingWindow>? ratingWindows,
      bool wasReturned = false,
      ReviewStage stage = ReviewStage.selfRating,
    }) =>
        MonthlyReview(
          id: 'r-${period.key}',
          employeeId: 'emp1',
          employeeName: 'Asha',
          managerId: 'mgr1',
          period: period,
          currentStage: stage,
          stageRecords: wasReturned
              ? {ReviewStage.reportingManagerRating: returnRecord()}
              : const {},
          rows: [r ?? row(self: 8)],
          ratingWindows: ratingWindows,
        );

    group('with no windows, today\'s rule exactly', () {
      test('the open month is the owner\'s to edit', () {
        expect(canEditSelfRating(review(september), owner, now), isTrue);
      });

      test('a closed, fully rated month is not', () {
        expect(canEditSelfRating(review(july), owner, now), isFalse);
      });

      test('a closed month reopens for a blank KRA, or when returned', () {
        expect(canEditSelfRating(review(july, r: row()), owner, now), isTrue);
        expect(canEditSelfRating(review(july, wasReturned: true), owner, now),
            isTrue);
      });

      test('a month still running never opens', () {
        expect(
            canEditSelfRating(review(october, r: row()), owner, now), isFalse);
      });

      test('identity, flow, completion and a missing scope all refuse', () {
        expect(canEditSelfRating(review(september), someoneElse, now), isFalse);
        expect(
            canEditSelfRating(review(september), adminOnlyOwner, now), isFalse);
        expect(
            canEditSelfRating(
                review(september, stage: ReviewStage.completed), owner, now),
            isFalse);
        expect(canEditSelfRating(review(september), null, now), isFalse);
      });
    });

    group('with a SELF window, the window decides when', () {
      test('open while its deadline runs', () {
        final r = review(september, ratingWindows: windows(september));
        expect(canEditSelfRating(r, owner, now), isTrue);
      });

      test('shut past it, even with a blank KRA or a rework flag', () {
        // Both would reopen it under the old rule. A return the server
        // honours arrives as a RETURNED window instead.
        expect(
            canEditSelfRating(
                review(august, r: row(), ratingWindows: windows(august)),
                owner,
                now),
            isFalse);
        expect(
            canEditSelfRating(
                review(august,
                    wasReturned: true, ratingWindows: windows(august)),
                owner,
                now),
            isFalse);
      });

      test('a RETURNED or OPENED window reopens a closed month', () {
        expect(
            canEditSelfRating(
                review(july,
                    ratingWindows: windows(
                        july, {ReviewStage.selfRating: returned(july)})),
                owner,
                now),
            isTrue);
        expect(
            canEditSelfRating(
                review(august,
                    ratingWindows: windows(august, {
                      ReviewStage.selfRating:
                          opened(august, ReviewStage.selfRating),
                    })),
                owner,
                now),
            isTrue,
            reason: 'a fully rated month too: a reopen is rate-and-edit');
      });

      test('CLOSED shuts the open month', () {
        final r = review(september,
            r: row(),
            ratingWindows: windows(september, {
              ReviewStage.selfRating:
                  forceClosed(september, ReviewStage.selfRating),
            }));
        expect(canEditSelfRating(r, owner, now), isFalse);
      });

      test('identity, flow and completion still apply inside an open window',
          () {
        final open = windows(september);
        expect(
            canEditSelfRating(
                review(september, ratingWindows: open), someoneElse, now),
            isFalse);
        expect(
            canEditSelfRating(
                review(september, ratingWindows: open), adminOnlyOwner, now),
            isFalse);
        expect(
            canEditSelfRating(
                review(september,
                    ratingWindows: open, stage: ReviewStage.completed),
                owner,
                now),
            isFalse);
      });

      test('another stage\'s window has no say over the self-rating', () {
        final r = review(september,
            ratingWindows: windows(september, {
              ReviewStage.reportingManagerRating:
                  forceClosed(september, ReviewStage.reportingManagerRating),
            }));
        expect(canEditSelfRating(r, owner, now), isTrue);
      });
    });
  });

  group('managerCanSubmitReview needs the reporting-manager window', () {
    MonthlyReview rated(ReviewPeriod period,
            [Map<ReviewStage, RatingWindow>? ratingWindows]) =>
        MonthlyReview(
          id: 'r-${period.key}',
          employeeId: 'emp1',
          employeeName: 'Asha',
          managerId: 'mgr1',
          period: period,
          currentStage: ReviewStage.reportingManagerRating,
          rows: [row(self: 8, ratedBy: ReviewStage.reportingManagerRating)],
          ratingWindows: ratingWindows,
        );

    test('offered while it is open', () {
      expect(
          managerCanSubmitReview(rated(september, windows(september)), 'mgr1',
              now: now),
          isTrue);
      expect(
          managerCanSubmitReview(
              rated(
                  august,
                  windows(august, {
                    ReviewStage.reportingManagerRating:
                        opened(august, ReviewStage.reportingManagerRating),
                  })),
              'mgr1',
              now: now),
          isTrue,
          reason: 'reopened past its deadline');
    });

    test('withheld once it has shut — the same data offered it before', () {
      expect(managerCanSubmitReview(rated(august), 'mgr1', now: now), isTrue,
          reason: 'no windows: the old rule allows a late submission');
      expect(
          managerCanSubmitReview(rated(august, windows(august)), 'mgr1',
              now: now),
          isFalse);
      expect(
          managerCanSubmitReview(
              rated(
                  september,
                  windows(september, {
                    ReviewStage.reportingManagerRating: forceClosed(
                        september, ReviewStage.reportingManagerRating),
                  })),
              'mgr1',
              now: now),
          isFalse);
    });

    test('only that stage\'s window counts', () {
      final r = rated(
          september,
          windows(september, {
            ReviewStage.selfRating:
                forceClosed(september, ReviewStage.selfRating),
          }));
      expect(managerCanSubmitReview(r, 'mgr1', now: now), isTrue);
    });
  });

  group('sendBackWindowsAllow', () {
    MonthlyReview atManager(ReviewPeriod period,
            [Map<ReviewStage, RatingWindow>? ratingWindows]) =>
        MonthlyReview(
          id: 'r-${period.key}',
          employeeId: 'emp1',
          employeeName: 'Asha',
          managerId: 'mgr1',
          period: period,
          currentStage: ReviewStage.reportingManagerRating,
          rows: [row(self: 8)],
          ratingWindows: ratingWindows,
        );

    test('no windows: unchanged, so always allowed here', () {
      expect(sendBackWindowsAllow(atManager(july), now), isTrue);
    });

    test('allowed while the manager\'s window is open', () {
      expect(
          sendBackWindowsAllow(atManager(september, windows(september)), now),
          isTrue);
    });

    test('a self window merely past its deadline does not block it', () {
      // The return itself reopens the self-rating, as a RETURNED window.
      final r = atManager(
          september,
          windows(september, {
            ReviewStage.selfRating: RatingWindow(
              source: RatingWindowSource.deadline,
              closed: false,
              opensAt: ist(2026, 10, 1),
              closesAt: ist(2026, 10, 1, 12),
            ),
          }));
      expect(sendBackWindowsAllow(r, now), isTrue);
    });

    test('refused while the self-rating is force-CLOSED', () {
      // The return would land on a stage nobody can act on.
      final r = atManager(
          september,
          windows(september, {
            ReviewStage.selfRating:
                forceClosed(september, ReviewStage.selfRating),
          }));
      expect(sendBackWindowsAllow(r, now), isFalse);
    });

    test('refused once the manager\'s own window has shut', () {
      expect(sendBackWindowsAllow(atManager(august, windows(august)), now),
          isFalse);
    });
  });

  group('managementSignOffReviews', () {
    MonthlyReview month(ReviewPeriod period,
            [Map<ReviewStage, RatingWindow>? ratingWindows]) =>
        MonthlyReview(
          id: 'r-${period.key}',
          employeeId: 'emp1',
          employeeName: 'Asha',
          period: period,
          currentStage: ReviewStage.managementReview,
          rows: [row(self: 8)],
          ratingWindows: ratingWindows,
        );

    test('no windows: every month present, as before', () {
      final quarter = [month(july), null, month(september)];
      expect(managementSignOffReviews(quarter, now).map((r) => r.period.key),
          ['2026-07', '2026-09']);
    });

    test('with windows: only months whose management window is open', () {
      final quarter = [
        month(july, windows(july)), // past 15 Aug
        month(
            august,
            windows(august, {
              ReviewStage.managementReview:
                  opened(august, ReviewStage.managementReview),
            })),
        month(september, windows(september)), // runs to 15 Oct
      ];
      expect(managementSignOffReviews(quarter, now).map((r) => r.period.key),
          ['2026-08', '2026-09']);
    });

    test('none open: nothing to act on, so no lock bar', () {
      final quarter = [
        month(july, windows(july)),
        month(august, windows(august))
      ];
      expect(managementSignOffReviews(quarter, now), isEmpty);
    });
  });
}
