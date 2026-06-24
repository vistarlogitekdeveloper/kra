import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../models/bulk_operation_result.dart';
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
          'pageSize': pageSize,
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
    String? department,
    String? projectLocationId,
    String? managerId,
    String? grade,
    double? monthlyIncentiveAmount,
    DateTime? joinedDate,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.employees,
        data: {
          'employeeCode': employeeCode,
          'name': fullName,
          'email': email,
          'role': role,
          if (department != null) 'department': department,
          if (projectLocationId != null) 'projectLocationId': projectLocationId,
          if (managerId != null) 'managerId': managerId,
          if (grade != null) 'grade': grade,
          if (monthlyIncentiveAmount != null)
            'monthlyIncentiveAmount': monthlyIncentiveAmount,
          if (joinedDate != null) 'joinedDate': joinedDate.toIso8601String(),
        },
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
  Future<BulkOperationResult> deactivateAll() async {
    final rows = await _fetchAllActive();
    return _runBulk<Employee>(
      rows,
      label: (e) => e.fullName,
      action: (e) => deactivate(e.id),
    );
  }

  @override
  Future<BulkOperationResult> clearAllIncentiveAmounts() async {
    final rows = await _fetchAllActive();
    return _runBulk<Employee>(
      rows,
      label: (e) => e.fullName,
      action: (e) => update(e.id, {'monthlyIncentiveAmount': 0}),
    );
  }

  /// Walks the paginated list endpoint until it exhausts. We can't trust
  /// a single high `pageSize` to return everything — the backend caps it
  /// (we hit that limit on the audit log probe earlier) — so loop in
  /// chunks of 50.
  Future<List<Employee>> _fetchAllActive() async {
    final out = <Employee>[];
    var page = 1;
    while (true) {
      final pageData = await list(page: page, pageSize: 50, isActive: true);
      out.addAll(pageData.employees);
      final fetched = page * 50;
      if (fetched >= pageData.total || pageData.employees.isEmpty) break;
      page += 1;
    }
    return out;
  }
}

/// Sequential bulk runner used by the admin-tools surfaces. Sequential
/// (not Future.wait) because Render's free tier throttles hard on bursts;
/// a parade of parallel DELETEs would return a mix of 200/429 and the
/// caller would see flaky failures unrelated to the data. Each item
/// failure is swallowed, recorded in [failures], and the loop continues.
Future<BulkOperationResult> _runBulk<T>(
  List<T> items, {
  required String Function(T item) label,
  required Future<void> Function(T item) action,
}) async {
  int ok = 0;
  int bad = 0;
  final failures = <String>[];
  for (final item in items) {
    try {
      await action(item);
      ok += 1;
    } catch (_) {
      bad += 1;
      if (failures.length < 5) failures.add(label(item));
    }
  }
  return BulkOperationResult(
    successCount: ok,
    failureCount: bad,
    failures: failures,
  );
}
