import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/api_error.dart';
import '../models/bulk_assign_result.dart';
import '../models/kra_assignment.dart';
import '../models/kra_template_item.dart';
import '../../../../core/api/envelope.dart';
import 'kra_assignment_repository.dart';

class ApiKraAssignmentRepository implements KraAssignmentRepository {
  final Dio _dio;
  ApiKraAssignmentRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<KraAssignment>> list({
    String? employeeId,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.kraAssignments,
        queryParameters: {
          if (employeeId != null && employeeId.isNotEmpty)
            'employeeId': employeeId,
        },
      );
      return unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(KraAssignment.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<KraAssignment> create({
    required String employeeId,
    String? templateId,
    List<KraTemplateItem>? items,
  }) async {
    try {
      final cycleId = await _resolveActiveCycleId();
      final response = await _dio.post(
        ApiConstants.kraAssignments,
        data: {
          'employeeId': employeeId,
          'cycleId': cycleId,
          if (templateId != null) 'templateId': templateId,
          if (items != null) 'items': items.map((e) => e.toJson()).toList(),
        },
      );
      return KraAssignment.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<KraAssignment> update(String id, Map<String, dynamic> changes) async {
    try {
      final response = await _dio.patch(
        '${ApiConstants.kraAssignments}/$id',
        data: changes,
      );
      return KraAssignment.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<BulkAssignResult> bulkAssign({
    required List<String> employeeIds,
    required String templateId,
  }) async {
    try {
      final cycleId = await _resolveActiveCycleId();
      final response = await _dio.post(
        ApiConstants.kraAssignmentsBulk,
        data: {
          'employeeIds': employeeIds,
          'templateId': templateId,
          'cycleId': cycleId,
        },
      );
      // Wire shape: { data: { createdCount, skippedCount,
      //                      skippedEmployeeIds, created: [...] } }
      // — see BulkAssignResult. Trying to parse as a List threw
      // BAD_RESPONSE on the happy path and the confirm screen surfaced
      // it as a failure even though the backend had saved everything.
      return BulkAssignResult.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  /// The live backend scopes every KRA assignment to a review cycle
  /// (`kra_assignments.cycle_id` is NOT NULL). The monthly UI has no cycle
  /// picker, so resolve it here: the first ACTIVE review cycle, falling
  /// back to the most recent one. Throws a clear error if none exists.
  Future<String> _resolveActiveCycleId() async {
    final response = await _dio.get(
      ApiConstants.reviewCycles,
      // Backend honours `limit`, not `pageSize`.
      queryParameters: {'page': 1, 'limit': 50},
    );
    final cycles =
        unwrapList(response).whereType<Map<String, dynamic>>().toList();
    if (cycles.isEmpty) {
      throw const ApiError(
        type: ApiErrorType.validation,
        code: 'NO_REVIEW_CYCLE',
        message: 'No review cycle exists yet, so KRAs can’t be assigned. '
            'Open a review cycle on the backend first.',
      );
    }
    final active = cycles.firstWhere(
      (c) => c['status']?.toString().toUpperCase() == 'ACTIVE',
      orElse: () => cycles.first,
    );
    final id = active['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const ApiError(
        type: ApiErrorType.validation,
        code: 'NO_REVIEW_CYCLE',
        message: 'Could not determine an active review cycle to assign into.',
      );
    }
    return id;
  }
}
