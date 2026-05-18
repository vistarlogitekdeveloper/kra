import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../models/incentive_summary.dart';
import 'my_incentive_repository.dart';

class ApiMyIncentiveRepository implements MyIncentiveRepository {
  final Dio _dio;
  ApiMyIncentiveRepository({required Dio dio}) : _dio = dio;

  @override
  Future<IncentiveSummary> fetchIncentiveSummary({
    required String cycleId,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.employeeIncentiveSummary,
        queryParameters: {'cycleId': cycleId},
      );
      return IncentiveSummary.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
