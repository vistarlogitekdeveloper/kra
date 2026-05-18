import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/api_error.dart';
import '../../../../core/api/envelope.dart';
import '../models/employee_profile.dart';
import 'my_profile_repository.dart';

class ApiMyProfileRepository implements MyProfileRepository {
  final Dio _dio;
  ApiMyProfileRepository({required Dio dio}) : _dio = dio;

  /// Fields the employee is allowed to PATCH on their own profile. The
  /// backend rejects anything else with 403 — enforcing client-side
  /// stops the request from leaving the device, makes the contract
  /// explicit at this boundary, and guards against a future caller
  /// passing through arbitrary keys without thinking.
  static const Set<String> _allowedPatchFields = {'phone', 'photoUrl'};

  @override
  Future<EmployeeProfile> fetchMyProfile() async {
    try {
      final response = await _dio.get(ApiConstants.employeeProfile);
      return EmployeeProfile.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<EmployeeProfile> updateMyProfile(
      Map<String, dynamic> changes) async {
    final filtered = <String, dynamic>{
      for (final entry in changes.entries)
        if (_allowedPatchFields.contains(entry.key)) entry.key: entry.value,
    };
    final rejected =
        changes.keys.where((k) => !_allowedPatchFields.contains(k));
    if (rejected.isNotEmpty) {
      // Surface as a typed ApiError so callers map it via the same path
      // as server-side validation failures. Code mirrors the backend's
      // 403 shape so analytics/dashboards see a single error class.
      throw ApiError(
        type: ApiErrorType.unknown,
        code: 'FORBIDDEN_FIELD',
        message:
            'Only the fields ${_allowedPatchFields.join(', ')} are editable.',
        statusCode: 403,
      );
    }
    try {
      final response = await _dio.patch(
        ApiConstants.employeeProfile,
        data: filtered,
      );
      return EmployeeProfile.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
