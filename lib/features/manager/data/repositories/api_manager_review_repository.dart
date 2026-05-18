import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../models/manager_review_detail.dart';
import 'manager_review_repository.dart';

class ApiManagerReviewRepository implements ManagerReviewRepository {
  final Dio _dio;
  ApiManagerReviewRepository({required Dio dio}) : _dio = dio;

  @override
  Future<ManagerReviewDetail> getReviewDetail(String reviewId) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.managerReviews}/$reviewId',
      );
      return ManagerReviewDetail.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ManagerReviewDetail> setManagerComment({
    required String reviewId,
    required String comment,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.managerReviews}/$reviewId/comment',
        data: {'comment': comment},
      );
      return ManagerReviewDetail.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
