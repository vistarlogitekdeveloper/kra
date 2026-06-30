import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../models/monthly_kra_row.dart';
import '../models/monthly_review.dart';
import '../models/monthly_review_summary.dart';
import '../models/review_stage.dart';
import 'monthly_review_repository.dart';

/// REST implementation of [MonthlyReviewRepository].
///
/// **Built against the PROPOSED contract documented on
/// [ApiConstants.monthlyReviews] — confirm endpoint paths + JSON shapes
/// against the real monthly backend before flipping
/// `monthlyReviewRepositoryProvider` off the mock.** The request/response
/// parsing reuses the app's envelope helpers and the model
/// `fromJson`/`toJson`, so reconciling with the live API is mostly a matter
/// of adjusting paths and field names.
///
/// Scope (own / team / org) is resolved server-side from the auth token +
/// role, so [ReviewScope] is not sent on reads.
class ApiMonthlyReviewRepository implements MonthlyReviewRepository {
  final Dio _dio;
  ApiMonthlyReviewRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<ReviewPeriod>> availablePeriods() async {
    try {
      final response = await _dio.get('${ApiConstants.monthlyReviews}/periods');
      return unwrapList(response)
          .whereType<String>()
          .map(ReviewPeriod.parse)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<List<MonthlyReviewSummary>> listForMonth({
    required ReviewPeriod period,
    required ReviewScope scope,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.monthlyReviews,
        queryParameters: {'period': period.key},
      );
      // The list endpoint returns full reviews; derive the lightweight
      // summary the dashboards render.
      return unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(MonthlyReview.fromJson)
          .map(MonthlyReviewSummary.fromReview)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<MonthlyReview> getReview(String reviewId) async {
    try {
      final response =
          await _dio.get('${ApiConstants.monthlyReviews}/$reviewId');
      return MonthlyReview.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<MonthlyReview> submitStage({
    required String reviewId,
    required ReviewStage stage,
    required ReviewScope actor,
    Map<String, RowScore>? rowScores,
    StageDecision? decision,
    String? comment,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.monthlyReviews}/$reviewId/stages/${stage.toApiString()}',
        data: {
          if (rowScores != null)
            'rowScores': rowScores.map((id, s) => MapEntry(id, s.toJson())),
          if (decision != null) 'decision': _decisionToApi(decision),
          if (comment != null) 'comment': comment,
        },
      );
      return MonthlyReview.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<MonthlyReview> markPaid({
    required String reviewId,
    required ReviewScope actor,
  }) async {
    try {
      final response =
          await _dio.post('${ApiConstants.monthlyReviews}/$reviewId/payout');
      return MonthlyReview.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  String _decisionToApi(StageDecision d) =>
      d == StageDecision.approve ? 'APPROVE' : 'RETURN_FOR_REWORK';
}
