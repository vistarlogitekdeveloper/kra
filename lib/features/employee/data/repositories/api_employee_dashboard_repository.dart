import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../models/employee_dashboard.dart';
import 'employee_dashboard_repository.dart';

class ApiEmployeeDashboardRepository implements EmployeeDashboardRepository {
  final Dio _dio;
  ApiEmployeeDashboardRepository({required Dio dio}) : _dio = dio;

  @override
  Future<EmployeeDashboard> fetchDashboard() async {
    try {
      final response = await _dio.get(ApiConstants.employeeDashboard);
      return EmployeeDashboard.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
