import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../../../../core/api/json_parse.dart';
import '../models/employee.dart';
import 'bulk_setup_repository.dart';

class ApiBulkSetupRepository implements BulkSetupRepository {
  final Dio _dio;
  ApiBulkSetupRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<Employee>> fetchEligibleEmployees({
    required String cycleId,
    String? locationId,
    String? role,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.employees,
        queryParameters: {
          'cycleId': cycleId,
          'eligible': 'true',
          if (locationId != null) 'projectLocationId': locationId,
          if (role != null) 'role': role,
        },
      );
      return unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(Employee.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<int> executeBulkSetup({
    required String cycleId,
    required String templateId,
    required List<String> employeeIds,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.kraAssignmentsBulk,
        data: {
          'cycleId': cycleId,
          'templateId': templateId,
          'employeeIds': employeeIds,
        },
      );
      final data = unwrapObject(response);
      return JsonParse.parseInt(data['count']) ?? employeeIds.length;
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
