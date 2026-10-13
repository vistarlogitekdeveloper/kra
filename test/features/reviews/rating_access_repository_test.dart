import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_access.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/repositories/rating_access_repository.dart';

/// The super-admin rating-access API (docs/RATING_ACCESS.md §3.5) as the
/// client speaks it: the organisation in the PATH, exact methods, and bodies
/// the server's validation accepts.
void main() {
  const august = ReviewPeriod(2026, 8);

  Map<String, dynamic> stageJson(String stage) => {
        'stage': stage,
        'window': {
          'source': 'DEADLINE',
          'closed': false,
          'opensAt': '2026-08-31T18:30:00.000Z',
          'closesAt': '2026-09-10T18:29:59.999Z',
          'deadlineAt': '2026-09-10T18:29:59.999Z',
        },
      };

  Map<String, dynamic> monthView() => {
        'success': true,
        'data': {
          'organizationId': 'org-1',
          'organizationName': 'Vistar Logitek',
          'reviewFlow': 'STANDARD',
          'period': '2026-08',
          'year': 2026,
          'month': 8,
          'stages': [
            for (final s in [
              'SELF_RATING',
              'REPORTING_MANAGER_RATING',
              'ACCOUNT_HR_RATING',
              'FINANCE_RATING',
              'MANAGEMENT_REVIEW',
            ])
              stageJson(s),
          ],
        },
      };

  Map<String, dynamic> overrideJson(String id, String stage, String updatedAt,
          {String mode = 'OPEN'}) =>
      {
        'id': id,
        'stage': stage,
        'period': '2026-07',
        'mode': mode,
        'openUntil': mode == 'OPEN' ? '2026-10-31T18:29:59.999Z' : null,
        'reason': 'Pre-opened at rollout: pending July/August ratings',
        'updatedAt': updatedAt,
        'updatedById': 'sa-1',
        'updatedByName': 'Super Admin',
      };

  ({ApiRatingAccessRepository repo, _CapturingAdapter http}) repoAnswering(
    Map<String, dynamic> body, {
    int status = 200,
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1/kra/'));
    final http = _CapturingAdapter((_) => (status: status, body: body));
    dio.httpClientAdapter = http;
    return (repo: ApiRatingAccessRepository(dio: dio), http: http);
  }

  group('reads', () {
    test('the month view: GET with the organisation and month in the path',
        () async {
      final r = repoAnswering(monthView());
      final month = await r.repo.fetchMonth('org-1', august);

      expect(r.http.only.method, 'GET');
      expect(r.http.only.path, '/organizations/org-1/rating-access/2026-08');
      expect(month.organizationName, 'Vistar Logitek');
      expect(month.period, august);
      expect(month.stages, hasLength(5));
    });

    test('path segments are encoded, so an id cannot address another route',
        () async {
      final r = repoAnswering(monthView());
      await r.repo.fetchMonth('org/1?x', august);
      expect(
          r.http.only.path, '/organizations/org%2F1%3Fx/rating-access/2026-08');
    });

    test('the history: GET overrides, unknown rows skipped, newest first',
        () async {
      final r = repoAnswering({
        'success': true,
        'data': [
          overrideJson('old', 'SELF_RATING', '2026-09-01T00:00:00.000Z'),
          overrideJson(
              'bogus', 'OPS_EXCELLENCE_SCORING', '2026-10-02T00:00:00.000Z'),
          overrideJson('new', 'FINANCE_RATING', '2026-10-01T00:00:00.000Z',
              mode: 'CLOSED'),
        ],
      });
      final list = await r.repo.fetchOverrides('org-1');

      expect(r.http.only.method, 'GET');
      expect(r.http.only.path, '/organizations/org-1/rating-access/overrides');
      expect([for (final o in list) o.id], ['new', 'old']);
      expect(list.first.mode, RatingAccessMode.closed);
      expect(list.first.openUntil, isNull);
      expect(list.last.period, const ReviewPeriod(2026, 7));
    });

    test('the history tolerates the list nested as data.overrides', () async {
      final r = repoAnswering({
        'success': true,
        'data': {
          'overrides': [
            overrideJson('a', 'SELF_RATING', '2026-09-01T00:00:00.000Z'),
          ],
        },
      });
      expect((await r.repo.fetchOverrides('org-1')).single.id, 'a');
    });
  });

  group('writes', () {
    test('open until a day: PUT with the date and a trimmed reason', () async {
      final r = repoAnswering(monthView());
      final month = await r.repo.setOverride(
        'org-1',
        august,
        ReviewStage.selfRating,
        mode: RatingAccessMode.open,
        openUntilDate: '2026-10-31',
        reason: '  Pending July ratings  ',
      );

      expect(r.http.only.method, 'PUT');
      expect(r.http.only.path,
          '/organizations/org-1/rating-access/2026-08/SELF_RATING');
      expect(r.http.only.data, {
        'mode': 'OPEN',
        'openUntilDate': '2026-10-31',
        'reason': 'Pending July ratings',
      });
      expect(month.period, august, reason: 'the month view comes back');
    });

    test('open with no end sends an explicit null and no blank reason',
        () async {
      final r = repoAnswering(monthView());
      await r.repo.setOverride(
        'org-1',
        august,
        ReviewStage.managementReview,
        mode: RatingAccessMode.open,
        reason: '   ',
      );

      final body = r.http.only.data as Map;
      expect(body, {'mode': 'OPEN', 'openUntilDate': null});
      expect(body.containsKey('openUntilDate'), isTrue);
      expect(body.containsKey('reason'), isFalse);
    });

    test('close never sends an end date, which the server would refuse',
        () async {
      final r = repoAnswering(monthView());
      await r.repo.setOverride(
        'org-1',
        august,
        ReviewStage.accountHrRating,
        mode: RatingAccessMode.closed,
        openUntilDate: '2026-10-31',
        reason: 'Audit in progress',
      );

      expect(r.http.only.path,
          '/organizations/org-1/rating-access/2026-08/ACCOUNT_HR_RATING');
      expect(
          r.http.only.data, {'mode': 'CLOSED', 'reason': 'Audit in progress'});
    });

    test('use deadline: DELETE the stage, the month view comes back', () async {
      final r = repoAnswering(monthView());
      final month = await r.repo
          .clearOverride('org-1', august, ReviewStage.financeRating);

      expect(r.http.only.method, 'DELETE');
      expect(r.http.only.path,
          '/organizations/org-1/rating-access/2026-08/FINANCE_RATING');
      expect(r.http.only.data, isNull);
      expect(month.stages, hasLength(5));
    });
  });

  group('failures arrive as ApiError', () {
    test('404 RES_001 — a backend without the endpoints', () async {
      final r = repoAnswering(
        {
          'success': false,
          'error': {'code': 'RES_001', 'message': 'Route not found'},
        },
        status: 404,
      );
      await expectLater(
        r.repo.fetchMonth('org-1', august),
        throwsA(isA<ApiError>()
            .having((e) => e.type, 'type', ApiErrorType.notFound)
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.code, 'code', 'RES_001')),
      );
    });

    test('400 VAL_001 keeps the server details for the snackbar', () async {
      final r = repoAnswering(
        {
          'success': false,
          'error': {
            'code': 'VAL_001',
            'message': 'Validation failed',
            'details': {
              'openUntilDate': ['openUntilDate is already in the past'],
            },
          },
        },
        status: 400,
      );
      await expectLater(
        r.repo.setOverride('org-1', august, ReviewStage.selfRating,
            mode: RatingAccessMode.open, openUntilDate: '2026-01-01'),
        throwsA(isA<ApiError>()
            .having((e) => e.type, 'type', ApiErrorType.validation)
            .having((e) => e.combinedMessage, 'combinedMessage',
                'openUntilDate is already in the past')),
      );
    });

    test('a month view with nothing readable is BAD_RESPONSE', () async {
      final r = repoAnswering({
        'success': true,
        'data': {'period': '2026-08', 'stages': []},
      });
      await expectLater(
        r.repo.fetchMonth('org-1', august),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'BAD_RESPONSE')),
      );
    });

    test('no connection is a network ApiError, not a raw DioException',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1/kra/'));
      dio.httpClientAdapter = _CapturingAdapter((options) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ));
      await expectLater(
        ApiRatingAccessRepository(dio: dio).fetchOverrides('org-1'),
        throwsA(isA<ApiError>()
            .having((e) => e.type, 'type', ApiErrorType.network)),
      );
    });
  });
}

/// Answers every request from [respond] and keeps what was asked.
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.respond);

  final ({int status, Map<String, dynamic> body}) Function(
      RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  /// The one request a test expects to have been made.
  RequestOptions get only {
    expect(requests, hasLength(1), reason: 'exactly one request');
    return requests.single;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final answer = respond(options);
    return ResponseBody.fromString(
      jsonEncode(answer.body),
      answer.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
