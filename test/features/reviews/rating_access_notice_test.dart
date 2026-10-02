import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/employee/presentation/widgets/_formatters.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_window.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The sheet's "reopened for rating" notice (docs/RATING_ACCESS.md §1).
///
/// A super admin's reopen makes cells editable that the calendar says are
/// shut. Unannounced, that reads as a bug — or nobody notices they can now
/// finish July. The lines must say WHICH months, until WHEN, and, when only
/// some seats were reopened, WHICH seats; anything less over-promises.
void main() {
  DateTime ist(int y, int m, int d, [int h = 0]) =>
      DateTime.utc(y, m, d, h).subtract(const Duration(hours: 5, minutes: 30));
  // Noon on 2 Oct 2026, IST.
  final now = ist(2026, 10, 2, 12);

  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);

  // Closing instants on the device's own calendar, so the expected date text
  // is the same in every timezone the suite runs in.
  final oct31 = DateTime(2026, 10, 31, 23, 59, 59, 999);
  final oct20 = DateTime(2026, 10, 20, 23, 59, 59, 999);

  final rating = ReviewStage.values.where((s) => s.isRatingStage).toList();

  RatingWindow w(
    ReviewPeriod month, {
    RatingWindowSource source = RatingWindowSource.deadline,
    DateTime? closesAt,
  }) {
    final n = month.next;
    return RatingWindow(
      source: source,
      closed: source == RatingWindowSource.closed,
      opensAt: ist(n.year, n.month, 1),
      closesAt: source == RatingWindowSource.closed
          ? null
          : (closesAt ?? ist(n.year, n.month, 10, 18)),
    );
  }

  RatingWindow reopened(ReviewPeriod m, DateTime? until) => RatingWindow(
        source: RatingWindowSource.opened,
        closed: false,
        opensAt: ist(m.next.year, m.next.month, 1),
        closesAt: until,
      );

  /// [month]'s review, every stage on its deadline except [overrides].
  MonthlyReview review(ReviewPeriod month,
          [Map<ReviewStage, RatingWindow> overrides = const {}]) =>
      MonthlyReview(
        id: 'r-${month.key}',
        employeeId: 'emp1',
        employeeName: 'Asha',
        period: month,
        ratingWindows: {
          for (final s in rating) s: w(month),
          ...overrides,
        },
      );

  Map<ReviewStage, RatingWindow> allReopened(ReviewPeriod m, DateTime? until) =>
      {for (final s in rating) s: reopened(m, until)};

  List<String> lines(List<MonthlyReview?> reviews,
          {ReviewFlow flow = ReviewFlow.standard}) =>
      reopenedNoticeLines(reviews, flow, now);

  group('the July/August rollout seed', () {
    test('reads as one line naming both months', () {
      expect(
        lines([
          review(july, allReopened(july, oct31)),
          review(august, allReopened(august, oct31)),
          review(september),
        ]),
        ['July 2026 and August 2026 reopened for rating until 31 Oct 2026.'],
      );
    });

    test('straight off the wire, equal instants still share one line', () {
      // Every stage of the month, opened to the end of 31 Oct IST.
      Map<String, Object?> seed(String opensAt) => {
            for (final s in rating)
              s.toApiString(): {
                'source': 'OPENED',
                'closed': false,
                'opensAt': opensAt,
                'closesAt': '2026-10-31T18:29:59.999Z',
              },
          };
      MonthlyReview parsed(String period, String opensAt) =>
          MonthlyReview.fromJson({
            'id': 'r-$period',
            'employeeId': 'emp1',
            'employeeName': 'Asha',
            'period': period,
            'ratingAccess': seed(opensAt),
          });

      final until = DateTime.utc(2026, 10, 31, 18, 29, 59, 999).toLocal();
      expect(
        lines([
          parsed('2026-07', '2026-07-31T18:30:00.000Z'),
          parsed('2026-08', '2026-08-31T18:30:00.000Z'),
        ]),
        [
          AppStrings.quarterlyReopenedUntil(
              'July 2026 and August 2026', EmployeeFormatters.date(until)),
        ],
      );
    });

    test('an administrators-only sheet ignores the self-rating it lacks', () {
      // The seed opens all five stages for every organisation. Under this
      // flow SELF is not a stage at all, so the four it has are "all".
      expect(
        lines([
          review(july, allReopened(july, oct31)),
          review(august, allReopened(august, oct31)),
        ], flow: ReviewFlow.adminOnly),
        ['July 2026 and August 2026 reopened for rating until 31 Oct 2026.'],
      );
    });
  });

  group('a partial reopen names its seats', () {
    test('a single stage', () {
      expect(
        lines([
          review(july),
          review(august, {
            ReviewStage.accountHrRating: reopened(august, oct20),
          }),
          review(september),
        ]),
        ['August 2026 (HR) reopened for rating until 20 Oct 2026.'],
      );
    });

    test('several stages, in pipeline order', () {
      expect(
        lines([
          review(august, {
            ReviewStage.accountHrRating: reopened(august, oct20),
            ReviewStage.selfRating: reopened(august, oct20),
          }),
        ]),
        [
          'August 2026 (Self-Rating, HR) reopened for rating until 20 Oct 2026.'
        ],
      );
    });

    test('a whole month and a partial one on the same date', () {
      expect(
        lines([
          review(july, allReopened(july, oct20)),
          review(august, {
            ReviewStage.financeRating: reopened(august, oct20),
          }),
        ]),
        [
          'July 2026 and August 2026 (Accounts) reopened for rating until '
              '20 Oct 2026.',
        ],
      );
    });

    test('the reporting-manager seat is named for whoever holds it', () {
      final managerOnly = [
        review(august, {
          ReviewStage.reportingManagerRating: reopened(august, oct20),
        }),
      ];
      expect(lines(managerOnly),
          ['August 2026 (Manager) reopened for rating until 20 Oct 2026.']);
      expect(lines(managerOnly, flow: ReviewFlow.adminOnly),
          ['August 2026 (Management) reopened for rating until 20 Oct 2026.']);
    });
  });

  group('one line per closing date', () {
    test('earliest first, a reopen with no end last', () {
      expect(
        lines([
          review(july, allReopened(july, null)),
          review(august, {
            ReviewStage.selfRating: reopened(august, oct31),
            ReviewStage.managementReview: reopened(august, oct20),
          }),
        ]),
        [
          'August 2026 (Management Review) reopened for rating until '
              '20 Oct 2026.',
          'August 2026 (Self-Rating) reopened for rating until 31 Oct 2026.',
          'July 2026 reopened for rating by the administrator.',
        ],
      );
    });

    test('months are listed in calendar order whatever order they arrive in',
        () {
      expect(
        lines([
          review(september, allReopened(september, oct31)),
          review(july, allReopened(july, oct31)),
          null,
          review(august, allReopened(august, oct31)),
        ]),
        [
          'July 2026, August 2026 and September 2026 reopened for rating '
              'until 31 Oct 2026.',
        ],
      );
    });
  });

  group('nothing to announce', () {
    test('an older backend sends no windows', () {
      expect(
        lines([
          const MonthlyReview(
              id: 'r', employeeId: 'e', employeeName: 'A', period: july),
          null,
        ]),
        isEmpty,
      );
    });

    test('deadlines, returns and closures are not reopens', () {
      expect(
        lines([
          review(july, {
            ReviewStage.selfRating:
                w(july, source: RatingWindowSource.returned, closesAt: oct31),
            ReviewStage.managementReview:
                w(july, source: RatingWindowSource.closed),
          }),
          review(september),
        ]),
        isEmpty,
      );
    });

    test('a reopen that has expired', () {
      expect(
        lines([
          review(july, allReopened(july, ist(2026, 9, 30, 23))),
        ]),
        isEmpty,
      );
    });

    test('a completed month, which no window reopens', () {
      final done = MonthlyReview(
        id: 'r-done',
        employeeId: 'emp1',
        employeeName: 'Asha',
        period: july,
        currentStage: ReviewStage.completed,
        ratingWindows: allReopened(july, oct31),
      );
      expect(lines([done]), isEmpty);
      expect(
        lines([done, review(august, allReopened(august, oct31))]),
        ['August 2026 reopened for rating until 31 Oct 2026.'],
      );
    });

    test('a reopen of a stage the flow does not have', () {
      expect(
        lines([
          review(july, {ReviewStage.selfRating: reopened(july, oct31)}),
        ], flow: ReviewFlow.adminOnly),
        isEmpty,
      );
    });
  });
}
