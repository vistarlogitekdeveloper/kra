import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../../../../core/api/json_parse.dart';
import '../models/my_review_detail.dart';
import '../models/my_review_summary.dart';
import 'my_review_repository.dart';

class ApiMyReviewRepository implements MyReviewRepository {
  final Dio _dio;
  ApiMyReviewRepository({required Dio dio}) : _dio = dio;

  @override
  Future<MyReviewPage> listMyReviews({
    String? cycleId,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.employeeReviews,
        queryParameters: {
          'page': page,
          // Backend honours `limit`, not `pageSize` (see EmployeeRepository).
          'limit': pageSize,
          if (cycleId != null && cycleId.isNotEmpty) 'cycleId': cycleId,
        },
      );
      final list = unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(MyReviewSummary.fromJson)
          .toList();
      // Pull total / page metadata from the meta block when present;
      // fall back to the list length so `hasMore` resolves cleanly even
      // if the backend hasn't started paginating yet.
      final meta = unwrapMeta(response);
      final total = JsonParse.parseInt(meta?['total']) ?? list.length;
      final apiPage = JsonParse.parseInt(meta?['page']) ?? page;
      final apiPageSize =
          JsonParse.parseInt(meta?['limit'] ?? meta?['pageSize']) ?? pageSize;
      return MyReviewPage(
        reviews: list,
        page: apiPage,
        pageSize: apiPageSize,
        total: total,
      );
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<MyReviewDetail> getReviewDetail(String reviewId) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.employeeReviews}/$reviewId',
      );
      return MyReviewDetail.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
