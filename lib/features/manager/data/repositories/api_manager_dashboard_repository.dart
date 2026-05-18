import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../models/manager_dashboard.dart';
import 'manager_dashboard_repository.dart';

class ApiManagerDashboardRepository implements ManagerDashboardRepository {
  final Dio _dio;
  ApiManagerDashboardRepository({required Dio dio}) : _dio = dio;

  @override
  Future<ManagerDashboard> fetchDashboard() async {
    try {
      final response = await _dio.get(ApiConstants.managerDashboard);
      return ManagerDashboard.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
