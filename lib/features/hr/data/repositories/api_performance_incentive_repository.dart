import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../models/performance_incentive.dart';
import '../../../../core/api/envelope.dart';
import 'performance_incentive_repository.dart';

class ApiPerformanceIncentiveRepository
    implements PerformanceIncentiveRepository {
  final Dio _dio;
  ApiPerformanceIncentiveRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<PerformanceIncentive>> listForCycle(String cycleId) async {
    try {
      final response = await _dio.get(
        ApiConstants.performanceIncentives,
        queryParameters: {'cycleId': cycleId},
      );
      return unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(PerformanceIncentive.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<PerformanceIncentive> create({
    required String cycleId,
    required String grade,
    required double monthlyEligibleAmount,
    required double quarterlyEligibleAmount,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.performanceIncentives,
        data: {
          'cycleId': cycleId,
          'grade': grade,
          'monthlyEligibleAmount': monthlyEligibleAmount,
          'quarterlyEligibleAmount': quarterlyEligibleAmount,
        },
      );
      return PerformanceIncentive.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<PerformanceIncentive> update(
      String id, Map<String, dynamic> changes) async {
    try {
      final response = await _dio.patch(
        '${ApiConstants.performanceIncentives}/$id',
        data: changes,
      );
      return PerformanceIncentive.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
