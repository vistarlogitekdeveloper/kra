import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/utils/monthly_deadlines.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/repositories/deadline_schedule_repository.dart';

/// The app follows the schedule the BACKEND is running.
///
/// The days are a published rule, but each instance can override them with
/// `KRA_*_DEADLINE_DAY`, and the backend's startup log states outright that the
/// app reads `GET /config/deadlines` and will follow those values. Until it
/// did, an override would have moved the reminder emails while every screen
/// kept counting to the frozen table — the same HR/Accounts drift this work
/// removed, reintroduced by configuration.
void main() {
  // The schedule is process-wide state, so no test may leak into the next.
  tearDown(DeadlineSchedule.reset);

  group('DeadlineSchedule', () {
    test('falls back to the published table until the server answers', () {
      expect(DeadlineSchedule.isResolved, isFalse);
      expect(ReviewStage.accountHrRating.deadlineDay, 12);
      expect(ReviewStage.incentivePayout.deadlineDay, 20);
      expect(DeadlineSchedule.overrides, isEmpty);
    });

    test('an adopted schedule wins, and MonthlyDeadlines follows it', () {
      DeadlineSchedule.adopt({ReviewStage.accountHrRating: 14});

      expect(ReviewStage.accountHrRating.deadlineDay, 14);
      // The whole point: everything downstream resolves through the same source.
      expect(
        MonthlyDeadlines.forStage(
            ReviewStage.accountHrRating, DateTime(2026, 6, 1)),
        DateTime(2026, 6, 14),
      );
      // Stages the server did not mention keep the published day.
      expect(ReviewStage.selfRating.deadlineDay, 10);
    });

    test('overrides name only the stages that actually differ', () {
      DeadlineSchedule.adopt({
        ReviewStage.selfRating: 10, // same as published
        ReviewStage.managementReview: 16, // different
      });

      expect(DeadlineSchedule.overrides, {ReviewStage.managementReview: 16});
    });

    test('an impossible day is ignored rather than shown to users', () {
      // A bad value would land in user-facing copy and in every countdown.
      DeadlineSchedule.adopt({
        ReviewStage.selfRating: 0,
        ReviewStage.managementReview: 32,
        ReviewStage.incentivePayout: 21,
      });

      expect(ReviewStage.selfRating.deadlineDay, 10, reason: 'published');
      expect(ReviewStage.managementReview.deadlineDay, 15, reason: 'published');
      expect(ReviewStage.incentivePayout.deadlineDay, 21, reason: 'accepted');
    });

    test('reset restores the published table', () {
      DeadlineSchedule.adopt({ReviewStage.selfRating: 3});
      expect(ReviewStage.selfRating.deadlineDay, 3);

      DeadlineSchedule.reset();
      expect(ReviewStage.selfRating.deadlineDay, 10);
      expect(DeadlineSchedule.isResolved, isFalse);
    });

    test('the terminal stage never has a day, whatever the server says', () {
      DeadlineSchedule.adopt({ReviewStage.completed: 28});
      // `completed` has no published day, so an adopted one would invent a
      // deadline for a finished review.
      expect(ReviewStage.completed.publishedDeadlineDay, isNull);
    });
  });

  group('reading it from the API', () {
    ApiDeadlineScheduleRepository repoReturning(
      Map<String, dynamic> body, {
      int status = 200,
    }) {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1/kra'));
      dio.httpClientAdapter = _StubAdapter(body: body, status: status);
      return ApiDeadlineScheduleRepository(dio: dio);
    }

    Map<String, dynamic> payload(Map<String, dynamic> deadlines) => {
          'success': true,
          'data': {
            'deadlines': deadlines,
            'reminderDays': {
              'SELF_RATING': [5, 8, 10]
            },
            'periodOffsetMonths': 1,
            'timezone': 'Asia/Kolkata',
            'overrides': [],
          },
        };

    test('parses the published table off the wire', () async {
      final result = await repoReturning(payload({
        'SELF_RATING': 10,
        'ACCOUNT_HR_RATING': 12,
        'FINANCE_RATING': 12,
        'REPORTING_MANAGER_RATING': 13,
        'MANAGEMENT_REVIEW': 15,
        'INCENTIVE_PAYOUT': 20,
      })).fetch();

      expect(result, {
        ReviewStage.selfRating: 10,
        ReviewStage.accountHrRating: 12,
        ReviewStage.financeRating: 12,
        ReviewStage.reportingManagerRating: 13,
        ReviewStage.managementReview: 15,
        ReviewStage.incentivePayout: 20,
      });
    });

    test('an UNKNOWN stage key is dropped, not filed under Self-Rating',
        () async {
      // ReviewStage.fromApi pins anything it does not recognise to selfRating so
      // a stray stage cannot take out a dashboard. Useful there — catastrophic
      // here, where it would silently move the self-rating deadline to whatever
      // day the unknown key carried.
      final result = await repoReturning(payload({
        'SELF_RATING': 10,
        'OPS_EXCELLENCE_SCORING': 27,
      })).fetch();

      expect(result, {ReviewStage.selfRating: 10});
    });

    test('decimal-as-string days parse, matching the rest of this API',
        () async {
      final result =
          await repoReturning(payload({'SELF_RATING': '10'})).fetch();
      expect(result, {ReviewStage.selfRating: 10});
    });

    test('a 404 from an older backend yields null, not a throw', () async {
      final result = await repoReturning(
        {
          'success': false,
          'error': {'code': 'NOT_FOUND', 'message': 'no'}
        },
        status: 404,
      ).fetch();

      expect(result, isNull);
    });

    test('a malformed or empty payload yields null', () async {
      expect(await repoReturning(payload({})).fetch(), isNull);
      expect(
        await repoReturning({
          'success': true,
          'data': {'deadlines': 'not-a-map'},
        }).fetch(),
        isNull,
      );
    });

    test('a null result leaves the published table alone', () async {
      // The contract the boot hook relies on: only a real schedule is adopted.
      final result = await repoReturning(payload({})).fetch();
      if (result != null) DeadlineSchedule.adopt(result);

      expect(ReviewStage.accountHrRating.deadlineDay, 12);
      expect(DeadlineSchedule.isResolved, isFalse);
    });
  });
}

class _StubAdapter implements HttpClientAdapter {
  final Map<String, dynamic> body;
  final int status;
  _StubAdapter({required this.body, required this.status});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}
