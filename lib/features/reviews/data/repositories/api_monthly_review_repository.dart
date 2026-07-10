import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../../../auth/data/models/user.dart';
import '../models/monthly_review.dart';
import '../models/monthly_review_summary.dart';
import '../models/review_stage.dart';
import '../models/row_score.dart';
import 'monthly_review_repository.dart';

/// Live [MonthlyReviewRepository] against the monthly-review backend
/// (`/reviews/monthly*`). Enable it via `_useMonthlyBackend` in
/// `monthly_review_providers.dart` once those endpoints are deployed.
///
/// The server scopes the list by the caller's JWT (employee → own, manager
/// → reports, HR/finance/admin → org) and reads the actor from the token,
/// so the scope-id / actor params on the contract aren't sent from here.
class ApiMonthlyReviewRepository implements MonthlyReviewRepository {
  final Dio _dio;
  ApiMonthlyReviewRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<MonthlyReviewSummary>> listMonthlyReviews({
    required int year,
    required int month,
    UserRole? scopeRole,
    String? scopeEmployeeId,
    String? scopeManagerId,
    ReviewStage? currentStage,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.monthlyReviews,
        queryParameters: {
          'year': year,
          'month': month,
          if (currentStage != null) 'currentStage': currentStage.toApiString(),
        },
      );
      return unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(MonthlyReviewSummary.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<MonthlyReview> getReview(String id) async {
    try {
      final response = await _dio.get('${ApiConstants.monthlyReviews}/$id');
      return MonthlyReview.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<MonthlyReview> submitStage(
    String reviewId,
    ReviewStage stage, {
    Map<String, RowScore>? rowScores,
    bool? approved,
    String? comment,
    required String actorId,
    required String actorName,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.monthlyReviews}/$reviewId/submit-stage',
        data: {
          'stage': stage.toApiString(),
          if (rowScores != null)
            'rowScores':
                rowScores.map((k, v) => MapEntry(k, v.toJson())),
          if (approved != null) 'approved': approved,
          if (comment != null) 'comment': comment,
        },
      );
      return MonthlyReview.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<MonthlyReview> markPaid(
    String reviewId, {
    required String actorId,
    required String actorName,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.monthlyReviews}/$reviewId/mark-paid',
      );
      return MonthlyReview.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
