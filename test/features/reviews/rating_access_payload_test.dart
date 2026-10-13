import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/api/error_text.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_window.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Rating access on the wire (docs/RATING_ACCESS.md §3.3–3.4): the windows a
/// review carries, and the refusal the server sends when one is shut.
///
/// Both are read by the sheet's gates, so a parse that silently dropped the
/// windows would put every gate back on the old rule while the server enforces
/// the new one — and a refusal read as anything but "closed" would tell the
/// employee their review had moved on.
void main() {
  /// The `ratingAccess` block exactly as `toFull` sends it, for August 2026:
  /// self past its deadline, HR reopened by a super admin, management closed.
  Map<String, Object?> ratingAccess() => {
        'SELF_RATING': {
          'source': 'DEADLINE',
          'closed': false,
          'opensAt': '2026-08-31T18:30:00.000Z',
          'closesAt': '2026-09-10T18:29:59.999Z',
          'deadlineAt': '2026-09-10T18:29:59.999Z',
        },
        'REPORTING_MANAGER_RATING': {
          'source': 'DEADLINE',
          'closed': false,
          'opensAt': '2026-08-31T18:30:00.000Z',
          'closesAt': '2026-09-13T18:29:59.999Z',
          'deadlineAt': '2026-09-13T18:29:59.999Z',
        },
        'ACCOUNT_HR_RATING': {
          'source': 'OPENED',
          'closed': false,
          'opensAt': '2026-08-31T18:30:00.000Z',
          'closesAt': '2026-10-31T18:29:59.999Z',
          'deadlineAt': '2026-09-12T18:29:59.999Z',
        },
        'FINANCE_RATING': {
          'source': 'DEADLINE',
          'closed': false,
          'opensAt': '2026-08-31T18:30:00.000Z',
          'closesAt': '2026-09-12T18:29:59.999Z',
          'deadlineAt': '2026-09-12T18:29:59.999Z',
        },
        'MANAGEMENT_REVIEW': {
          'source': 'CLOSED',
          'closed': true,
          'opensAt': '2026-08-31T18:30:00.000Z',
          'closesAt': null,
          'deadlineAt': '2026-09-15T18:29:59.999Z',
        },
      };

  Map<String, dynamic> reviewJson({bool withAccess = true}) => {
        'id': 'r-aug',
        'employeeId': 'emp1',
        'employeeName': 'Asha',
        'period': '2026-08',
        'currentStage': 'SELF_RATING',
        'rows': [
          {
            'id': 'row-1',
            'name': 'Safety of the Facility',
            'weightagePercent': 100,
            'maxScore': 10,
          },
        ],
        'managementLockedAt': null,
        if (withAccess) 'ratingAccess': ratingAccess(),
      };

  group('MonthlyReview.ratingWindows', () {
    test('parses all five stages from ratingAccess', () {
      final r = MonthlyReview.fromJson(reviewJson());
      expect(r.ratingWindows?.keys,
          unorderedEquals(ReviewStage.values.where((s) => s.isRatingStage)));
      expect(r.windowFor(ReviewStage.accountHrRating)?.source,
          RatingWindowSource.opened);
      expect(r.windowFor(ReviewStage.accountHrRating)?.closesAt,
          DateTime.utc(2026, 10, 31, 18, 29, 59, 999));
      expect(r.windowFor(ReviewStage.managementReview)?.closed, isTrue);
      expect(r.windowFor(ReviewStage.incentivePayout), isNull,
          reason: 'payout is never gated');
    });

    test('absent means an older backend: no windows at all', () {
      final r = MonthlyReview.fromJson(reviewJson(withAccess: false));
      expect(r.ratingWindows, isNull);
      for (final s in ReviewStage.values) {
        expect(r.windowFor(s), isNull, reason: '$s');
      }
    });

    test('copyWith carries the windows — it runs on every sheet load', () {
      final r = MonthlyReview.fromJson(reviewJson());
      final remapped = r.copyWith(
        rows: [
          for (final row in r.rows) row.copyWith(displayOrder: 3),
        ],
      );
      expect(remapped.ratingWindows, r.ratingWindows);
      expect(r.copyWith().ratingWindows, r.ratingWindows);
    });

    test('toJson round-trips them, and omits them when there are none', () {
      final r = MonthlyReview.fromJson(reviewJson());
      final back = MonthlyReview.fromJson(r.toJson());
      expect(back.ratingWindows, r.ratingWindows);

      final legacy = MonthlyReview.fromJson(reviewJson(withAccess: false));
      expect(legacy.toJson().containsKey('ratingAccess'), isFalse);
      expect(MonthlyReview.fromJson(legacy.toJson()).ratingWindows, isNull);
    });
  });

  group('the AUTHZ_RATING_CLOSED refusal', () {
    // §3.3: a 403 whose `details` holds ONE nested object.
    ApiError refusal({
      int status = 403,
      String code = 'AUTHZ_RATING_CLOSED',
      String message = 'Self-rating for August 2026 closed on 10 Sep 2026.',
    }) {
      final req = RequestOptions(path: '/reviews/monthly/r-aug/save-scores');
      return ApiError.fromDioException(DioException(
        requestOptions: req,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: req,
          statusCode: status,
          data: {
            'success': false,
            'error': {
              'code': code,
              'message': message,
              'details': {
                'ratingAccess': {
                  'stage': 'SELF_RATING',
                  'period': '2026-08',
                  'source': 'DEADLINE',
                  'opensAt': '2026-08-31T18:30:00.000Z',
                  'closesAt': '2026-09-10T18:29:59.999Z',
                },
              },
            },
          },
        ),
      ));
    }

    test('is recognised by its code', () {
      final e = refusal();
      expect(e.isRatingClosed, isTrue);
      expect(e.statusCode, 403);
    });

    test('stops the manager\'s multi-month submit instead of being skipped',
        () async {
      // submitEachSkippingMoved skips only 409s — "that month moved on". A
      // closed window is not that, and must reach the user.
      final quarter = [
        for (final m in [7, 8, 9])
          MonthlyReview(
            id: 'r-$m',
            employeeId: 'emp1',
            employeeName: 'Asha',
            period: ReviewPeriod(2026, m),
          ),
      ];
      final attempted = <String>[];
      await expectLater(
        submitEachSkippingMoved(quarter, (r) async {
          attempted.add(r.period.key);
          if (r.period.month == 8) throw refusal();
        }),
        throwsA(isA<ApiError>()
            .having((e) => e.isRatingClosed, 'isRatingClosed', isTrue)),
      );
      expect(attempted, ['2026-07', '2026-08']);
    });

    test('shows the server\'s sentence verbatim', () {
      // The nested details object is not a field error, so it must not
      // replace the message the way a flat string in `details` would.
      final e = refusal(
          message: 'Self-rating for August 2026 has been closed by the '
              'administrator.');
      expect(e.combinedMessage,
          'Self-rating for August 2026 has been closed by the administrator.');
      expect(userFacingError(e), e.combinedMessage);
    });

    test('other refusals are not mistaken for it', () {
      expect(refusal(status: 409, code: 'RES_002').isRatingClosed, isFalse);
      expect(refusal(code: 'AUTHZ_001').isRatingClosed, isFalse);
    });
  });
}
