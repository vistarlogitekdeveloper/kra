import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
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
    String? cycleId,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.kraAssignments,
        queryParameters: {
          if (employeeId != null && employeeId.isNotEmpty)
            'employeeId': employeeId,
          if (cycleId != null && cycleId.isNotEmpty) 'cycleId': cycleId,
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
    required String cycleId,
    String? templateId,
    List<KraTemplateItem>? items,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.kraAssignments,
        data: {
          'employeeId': employeeId,
          'cycleId': cycleId,
          if (templateId != null) 'templateId': templateId,
          if (items != null)
            'items': items.map((e) => e.toJson()).toList(),
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
    required String cycleId,
    required String templateId,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.kraAssignmentsBulk,
        data: {
          'employeeIds': employeeIds,
          'cycleId': cycleId,
          'templateId': templateId,
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
}
