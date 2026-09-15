import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../models/employee.dart';
import '../../../../core/api/envelope.dart';
import 'employee_repository.dart';

/// REST-backed [EmployeeRepository] using the shared Dio instance.
class ApiEmployeeRepository implements EmployeeRepository {
  final Dio _dio;
  ApiEmployeeRepository({required Dio dio}) : _dio = dio;

  @override
  Future<EmployeePage> list({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? role,
    bool? isActive,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.employees,
        queryParameters: {
          'page': page,
          // Backend honours `limit`, not `pageSize` — sending pageSize was
          // silently ignored (defaulted to 50), capping the list past 50
          // employees. Matches the manager/locations/audit repos.
          'limit': pageSize,
          if (search != null && search.isNotEmpty) 'search': search,
          if (role != null && role.isNotEmpty) 'role': role,
          if (isActive != null) 'isActive': isActive,
        },
      );
      return EmployeePage.fromJson(unwrapPaged(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<Employee> getById(String id) async {
    try {
      final response = await _dio.get('${ApiConstants.employees}/$id');
      return Employee.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<Employee> create({
    required String employeeCode,
    required String fullName,
    required String email,
    required String role,
    List<String>? roles,
    String? position,
    String? department,
    String? projectLocationId,
    String? managerId,
    String? grade,
    double? monthlyIncentiveAmount,
    DateTime? joinedDate,
    String? password,
    bool? forcePasswordReset,
    String? organizationId,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.employees,
        data: {
          'employeeCode': employeeCode,
          'name': fullName,
          'email': email,
          'role': role,
          // Multi-role grant set. Omitted unless the caller supplies one, since
          // an unrecognised field would 400 every create on a server that only
          // knows the scalar `role`.
          if (roles != null && roles.isNotEmpty) 'roles': roles,
          if (position != null) 'position': position,
          if (department != null) 'department': department,
          if (projectLocationId != null) 'projectLocationId': projectLocationId,
          if (managerId != null) 'managerId': managerId,
          if (grade != null) 'grade': grade,
          if (monthlyIncentiveAmount != null)
            'monthlyIncentiveAmount': monthlyIncentiveAmount,
          if (joinedDate != null) 'joinedDate': joinedDate.toIso8601String(),
          // Target tenant for a super-admin create. Omitted otherwise so a
          // server without the field cannot 400 an ordinary create.
          if (organizationId != null && organizationId.isNotEmpty)
            'organizationId': organizationId,
          // Login credentials — optional on the wire. Backend defaults
          // authMethod to PASSWORD when omitted; sending a value here
          // makes the new account log-in-able with that password.
          if (password != null && password.isNotEmpty) 'password': password,
          if (forcePasswordReset != null)
            'forcePasswordReset': forcePasswordReset,
        },
      );
      return Employee.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<Employee> transfer(String id, String organizationId) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.employees}/$id/transfer',
        data: {'organizationId': organizationId},
      );
      return Employee.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<Employee> update(String id, Map<String, dynamic> changes) async {
    try {
      final response = await _dio.patch(
        '${ApiConstants.employees}/$id',
        data: changes,
      );
      return Employee.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<void> deactivate(String id) async {
    try {
      await _dio.delete('${ApiConstants.employees}/$id');
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<Employee> setPassword(
    String id, {
    required String password,
    bool forcePasswordReset = false,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.employees}/$id/set-password',
        data: {
          'password': password,
          'forcePasswordReset': forcePasswordReset,
        },
      );
      return Employee.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
