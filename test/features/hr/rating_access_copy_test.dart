import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/hr/presentation/widgets/rating_access/rating_access_copy.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_access.dart';
import 'package:vistar_app/features/reviews/data/models/rating_window.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

import 'rating_access_fakes.dart';

/// Every line the rating-access screen shows a super admin, derived only from
/// the window the server resolved and the clock.
///
/// Dates go through [ratingAccessDate], which formats on the device's
/// calendar; expectations are built through it too so the suite passes in any
/// timezone, and one test pins the format itself with a mid-day instant.
void main() {
  // 2 Oct 2026, 12:00 IST.
  final now = DateTime.utc(2026, 10, 2, 6, 30);
  String d(DateTime instant) => ratingAccessDate(instant);

  group('dates', () {
    test("are written 'd MMM yyyy'", () {
      expect(ratingAccessDate(DateTime.utc(2026, 9, 10, 12)), '10 Sep 2026');
    });

    test('an open-until day goes out as YYYY-MM-DD', () {
      expect(ratingAccessDateParam(DateTime(2026, 10, 1)), '2026-10-01');
    });

    test('the sheet starts on the current end when ahead, else today', () {
      final today = DateTime(2026, 10, 2);
      expect(ratingAccessDefaultOpenDay(null, today), today);
      expect(
          ratingAccessDefaultOpenDay(DateTime(2026, 9, 1, 12), today), today);
      expect(ratingAccessDefaultOpenDay(DateTime(2026, 10, 31, 12), today),
          DateTime(2026, 10, 31));
      expect(ratingAccessDefaultOpenDay(DateTime(2031, 1, 1), today),
          ratingAccessLastOpenDay(today),
          reason: 'never past what the date picker allows');
      expect(ratingAccessLastOpenDay(today), DateTime(2027, 10, 2));
    });
  });

  group('ratingAccessPhase', () {
    final opens = istMonthStart(2026, 9);
    final deadline = istEndOfDay(2026, 9, 10);
    RatingWindow w(RatingWindowSource source,
            {bool closed = false, DateTime? closesAt, bool noEnd = false}) =>
        RatingWindow(
          source: source,
          closed: closed,
          opensAt: opens,
          closesAt: noEnd ? null : (closesAt ?? deadline),
          deadlineAt: deadline,
        );
    const ms = Duration(milliseconds: 1);

    test('nothing is open before the month ends', () {
      expect(
          ratingAccessPhase(w(RatingWindowSource.deadline), opens.subtract(ms)),
          RatingAccessPhase.notYetOpen);
      expect(
          ratingAccessPhase(
              w(RatingWindowSource.opened, noEnd: true), opens.subtract(ms)),
          RatingAccessPhase.notYetOpen);
    });

    test('the deadline rule, inclusive at both ends', () {
      final d = w(RatingWindowSource.deadline);
      expect(ratingAccessPhase(d, opens), RatingAccessPhase.deadlineOpen);
      expect(ratingAccessPhase(d, deadline), RatingAccessPhase.deadlineOpen);
      expect(ratingAccessPhase(d, deadline.add(ms)),
          RatingAccessPhase.deadlineClosed);
    });

    test('a reopen is open until its end, then ended', () {
      final end = istEndOfDay(2026, 10, 31);
      final r = w(RatingWindowSource.opened, closesAt: end);
      expect(ratingAccessPhase(r, end), RatingAccessPhase.reopened);
      expect(ratingAccessPhase(r, end.add(ms)), RatingAccessPhase.reopenEnded);
      expect(
          ratingAccessPhase(
              w(RatingWindowSource.opened, noEnd: true), DateTime.utc(2030)),
          RatingAccessPhase.reopened);
    });

    test('closed by the admin whatever the instants say, failing closed', () {
      expect(
          ratingAccessPhase(
              w(RatingWindowSource.closed, closed: true, noEnd: true), opens),
          RatingAccessPhase.closedByAdmin);
      // A CLOSED source whose flag disagrees still reads closed.
      expect(ratingAccessPhase(w(RatingWindowSource.closed), opens),
          RatingAccessPhase.closedByAdmin);
    });

    test('a returned self-rating with no end reads as open', () {
      expect(
          ratingAccessPhase(
              w(RatingWindowSource.returned, noEnd: true), DateTime.utc(2027)),
          RatingAccessPhase.deadlineOpen);
    });
  });

  group('stage labels follow the seat', () {
    test('standard', () {
      expect(
        [
          for (final s in ratingStages)
            ratingAccessStageLabel(s, ReviewFlow.standard),
        ],
        [
          'Self-rating',
          'Reporting-manager rating',
          'HR rating',
          'Accounts rating',
          'Management review',
        ],
      );
    });

    test('administrators-only: the manager seat is management', () {
      expect(
          ratingAccessStageLabel(
              ReviewStage.reportingManagerRating, ReviewFlow.adminOnly),
          'Management rating');
      expect(
          ratingAccessSeatDescription(
              ReviewStage.reportingManagerRating, ReviewFlow.adminOnly),
          AppStrings.ratingAccessSeatManagementRating);
      expect(
          ratingAccessSeatDescription(
              ReviewStage.reportingManagerRating, ReviewFlow.standard),
          AppStrings.ratingAccessSeatReportingManager);
    });
  });

  group('status lines', () {
    test('open on the deadline', () {
      final w = deadlineWindow(september, ReviewStage.selfRating);
      expect(ratingAccessStatusLine(w, now),
          'Open until ${d(istEndOfDay(2026, 10, 10))} · deadline');
    });

    test('closed after the deadline', () {
      final w = deadlineWindow(august, ReviewStage.reportingManagerRating);
      expect(ratingAccessStatusLine(w, now),
          'Closed on ${d(istEndOfDay(2026, 9, 13))} · deadline');
    });

    test('not yet open — the month has not ended', () {
      const october = ReviewPeriod(2026, 10);
      expect(
          ratingAccessStatusLine(
              deadlineWindow(october, ReviewStage.selfRating), now),
          'Opens ${d(istMonthStart(2026, 11))}');
      expect(
        ratingAccessStatusLine(
            openedWindow(october, ReviewStage.selfRating,
                until: istEndOfDay(2026, 11, 30)),
            now),
        'Opens ${d(istMonthStart(2026, 11))} · reopened until '
        '${d(istEndOfDay(2026, 11, 30))}',
      );
      expect(
          ratingAccessStatusLine(
              openedWindow(october, ReviewStage.selfRating), now),
          'Opens ${d(istMonthStart(2026, 11))} · reopened, no end date');
    });

    test('reopened, with and without an end', () {
      final end = istEndOfDay(2026, 10, 31);
      expect(
          ratingAccessStatusLine(
              openedWindow(august, ReviewStage.selfRating, until: end), now),
          'Reopened until ${d(end)}');
      expect(
          ratingAccessStatusLine(
              openedWindow(august, ReviewStage.financeRating), now),
          'Reopened · no end date');
    });

    test('a reopen that has run out reads as closed', () {
      final end = istEndOfDay(2026, 10, 31);
      expect(
        ratingAccessStatusLine(
          openedWindow(august, ReviewStage.selfRating, until: end),
          end.add(const Duration(milliseconds: 1)),
        ),
        'Closed on ${d(end)} · reopen ended',
      );
    });

    test('closed by the super admin', () {
      expect(
          ratingAccessStatusLine(
              closedWindow(august, ReviewStage.accountHrRating), now),
          'Closed by super admin');
    });
  });

  group('the override behind a status', () {
    test('summaries for the history', () {
      final end = istEndOfDay(2026, 10, 31);
      expect(
          ratingAccessOverrideSummary(
              overrideOf(august, ReviewStage.selfRating, RatingAccessMode.open,
                  openUntil: end),
              now),
          'Open until ${d(end)}');
      expect(
          ratingAccessOverrideSummary(
              overrideOf(august, ReviewStage.selfRating, RatingAccessMode.open,
                  openUntil: end),
              end.add(const Duration(days: 1))),
          'Open until ${d(end)} · ended');
      expect(
          ratingAccessOverrideSummary(
              overrideOf(august, ReviewStage.selfRating, RatingAccessMode.open),
              now),
          'Open · no end date');
      expect(
          ratingAccessOverrideSummary(
              overrideOf(
                  august, ReviewStage.selfRating, RatingAccessMode.closed),
              now),
          'Closed');
    });

    test('who changed it and when, as much as the server sent', () {
      final at = DateTime.utc(2026, 10, 1, 4, 30);
      RatingAccessOverride by(String? name, DateTime? updatedAt) =>
          RatingAccessOverride(
            id: 'o',
            stage: ReviewStage.selfRating,
            period: august,
            mode: RatingAccessMode.closed,
            updatedAt: updatedAt,
            updatedByName: name,
          );
      expect(ratingAccessUpdatedLine(by('Super Admin', at)),
          'by Super Admin · ${d(at)}');
      expect(ratingAccessUpdatedLine(by('  ', at)), 'Updated ${d(at)}');
      expect(
          ratingAccessUpdatedLine(by('Super Admin', null)), 'by Super Admin');
      expect(ratingAccessUpdatedLine(by(null, null)), isNull);
    });
  });

  group('month chips', () {
    const available = [september, august, july];

    test('the available months as they are', () {
      expect(ratingAccessChipPeriods(available, august), available);
    });

    test('a month from a link or the history is added in order', () {
      expect(ratingAccessChipPeriods(available, const ReviewPeriod(2026, 10)),
          [const ReviewPeriod(2026, 10), september, august, july]);
      expect(ratingAccessChipPeriods(available, const ReviewPeriod(2026, 1)),
          [september, august, july, const ReviewPeriod(2026, 1)]);
    });
  });

  group('errors', () {
    test('a 404 or RES_001 says the endpoints are not deployed', () {
      expect(
        ratingAccessErrorText(const ApiError(
            type: ApiErrorType.notFound,
            code: 'NOT_FOUND',
            message: 'x',
            statusCode: 404)),
        AppStrings.ratingAccessApiMissing,
      );
      expect(
        ratingAccessErrorText(const ApiError(
            type: ApiErrorType.unknown, code: 'RES_001', message: 'x')),
        AppStrings.ratingAccessApiMissing,
      );
    });

    test("anything else is the server's message, never a debug dump", () {
      expect(
        ratingAccessErrorText(const ApiError(
          type: ApiErrorType.validation,
          code: 'VAL_001',
          message: 'Validation failed',
          statusCode: 400,
          fieldErrors: {
            'openUntilDate': ['That date has already passed.'],
          },
        )),
        'That date has already passed.',
      );
      expect(
          ratingAccessErrorText(StateError('boom')), AppStrings.errorGeneric);
    });
  });
}
