import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../../../../core/api/json_parse.dart';
import '../models/manager_rate_request.dart';
import '../models/manager_rate_response.dart';
import 'manager_rate_repository.dart';

class ApiManagerRateRepository implements ManagerRateRepository {
  final Dio _dio;
  ApiManagerRateRepository({required Dio dio}) : _dio = dio;

  @override
  Future<int> autoSaveScores({
    required String reviewId,
    required ManagerRateRequest scores,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.reviewsScores}/$reviewId/scores',
        data: {
          // The shared scores endpoint expects `side` to disambiguate
          // manager vs employee saves. Always 'MANAGER' here.
          'side': 'MANAGER',
          'scores': scores.scores.map((s) => s.toJson()).toList(),
          if (scores.managerComment != null)
            'managerComment': scores.managerComment,
        },
      );
      final data = unwrapObject(response);
      return JsonParse.parseInt(data['savedCount']) ?? scores.scores.length;
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ManagerRateResponse> submitRating({
    required String reviewId,
    required ManagerRateRequest request,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.managerReviews}/$reviewId/manager-rate',
        data: request.toJson(),
      );
      return ManagerRateResponse.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ManagerRateResponse> updateRating({
    required String reviewId,
    required ManagerRateRequest request,
  }) async {
    try {
      final response = await _dio.patch(
        '${ApiConstants.managerReviews}/$reviewId/manager-rate',
        data: request.toJson(),
      );
      return ManagerRateResponse.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
