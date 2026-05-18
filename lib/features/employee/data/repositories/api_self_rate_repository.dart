import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../models/my_review_detail.dart';
import '../models/self_rate_request.dart';
import 'self_rate_repository.dart';

class ApiSelfRateRepository implements SelfRateRepository {
  final Dio _dio;
  ApiSelfRateRepository({required Dio dio}) : _dio = dio;

  @override
  Future<MyReview> submitSelfRating({
    required String reviewId,
    required SelfRateRequest request,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.employeeReviews}/$reviewId/self-rate',
        data: request.toJson(),
      );
      return MyReview.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
