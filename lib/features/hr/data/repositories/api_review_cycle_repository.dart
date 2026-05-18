import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../models/review_cycle.dart';
import '../../../../core/api/envelope.dart';
import 'review_cycle_repository.dart';

class ApiReviewCycleRepository implements ReviewCycleRepository {
  final Dio _dio;
  ApiReviewCycleRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<ReviewCycle>> list({ReviewCycleStatus? status}) async {
    try {
      final response = await _dio.get(
        ApiConstants.reviewCycles,
        queryParameters: {
          if (status != null) 'status': status.toApiString(),
        },
      );
      return unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(ReviewCycle.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ReviewCycle> getById(String id) async {
    try {
      final response = await _dio.get('${ApiConstants.reviewCycles}/$id');
      return ReviewCycle.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ReviewCycle> create({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    DateTime? selfRatingDeadline,
    DateTime? managerReviewDeadline,
    DateTime? opsScoringDeadline,
    DateTime? financeScoringDeadline,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.reviewCycles,
        data: {
          'name': name,
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
          if (selfRatingDeadline != null)
            'selfRatingDeadline': selfRatingDeadline.toIso8601String(),
          if (managerReviewDeadline != null)
            'managerReviewDeadline': managerReviewDeadline.toIso8601String(),
          if (opsScoringDeadline != null)
            'opsScoringDeadline': opsScoringDeadline.toIso8601String(),
          if (financeScoringDeadline != null)
            'financeScoringDeadline': financeScoringDeadline.toIso8601String(),
        },
      );
      return ReviewCycle.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ReviewCycle> update(String id, Map<String, dynamic> changes) async {
    try {
      final response = await _dio.patch(
        '${ApiConstants.reviewCycles}/$id',
        data: changes,
      );
      return ReviewCycle.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ReviewCycle> activate(String id) async {
    try {
      final response =
          await _dio.post('${ApiConstants.reviewCycles}/$id/activate');
      return ReviewCycle.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ReviewCycle> close(String id) async {
    try {
      final response =
          await _dio.post('${ApiConstants.reviewCycles}/$id/close');
      return ReviewCycle.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
