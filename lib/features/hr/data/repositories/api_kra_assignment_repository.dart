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
      final cycleId = await _resolveOrCreateActiveCycleId();
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
      final cycleId = await _resolveOrCreateActiveCycleId();
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

  // ── Automatic review-cycle resolution ────────────────────────────────────
  // KRA reviews run monthly and pay out quarterly, and HR shouldn't have to
  // open a cycle by hand. Every assignment needs a cycle (the live backend's
  // `kra_assignments.cycle_id` is NOT NULL), so we resolve one automatically:
  // use the ACTIVE cycle, else activate an existing one, else create + activate
  // the CURRENT QUARTER's cycle — all silently, via the backend's own cycle
  // endpoints. No dialog, no prompt.
  Future<String> _resolveOrCreateActiveCycleId() async {
    final listRes = await _dio.get(
      ApiConstants.reviewCycles,
      queryParameters: {'page': 1, 'limit': 50},
    );
    final cycles =
        unwrapList(listRes).whereType<Map<String, dynamic>>().toList();
    if (cycles.isNotEmpty) {
      final active = cycles.firstWhere(
        (c) => (c['status']?.toString().toUpperCase()) == 'ACTIVE',
        orElse: () => cycles.first,
      );
      final id = active['id']?.toString();
      if (id != null && id.isNotEmpty) {
        // Make sure it's live before assigning into it.
        if ((active['status']?.toString().toUpperCase()) != 'ACTIVE') {
          await _activateCycle(id);
        }
        return id;
      }
    }
    return _createAndActivateCurrentQuarterCycle();
  }

  Future<void> _activateCycle(String id) async {
    await _dio.post('${ApiConstants.reviewCycles}/$id/activate');
  }

  Future<String> _createAndActivateCurrentQuarterCycle() async {
    final now = DateTime.now();
    final y = now.year;
    final m = now.month; // 1-12
    final qStartMonth = ((m - 1) ~/ 3) * 3 + 1; // 1, 4, 7, 10
    final startDate = DateTime(y, qStartMonth, 1);
    final endDate = DateTime(y, qStartMonth + 3, 0); // last day of the quarter
    // Indian financial year (starts in April); the calendar-quarter window
    // aligns with a fiscal quarter, so number + label it by FY.
    final fyStart = m >= 4 ? y : y - 1;
    final fyLabel = 'FY $fyStart-'
        '${((fyStart + 1) % 100).toString().padLeft(2, '0')}';
    final quarterNum = ((m - 4 + 12) % 12) ~/ 3 + 1; // FY Q1 = Apr–Jun
    // Deadlines cascade after the end date, in the order the backend enforces.
    final self = endDate.add(const Duration(days: 5));
    final manager = self.add(const Duration(days: 3));
    final ops = manager.add(const Duration(days: 2));
    final finance = ops.add(const Duration(days: 2));

    final createRes = await _dio.post(
      ApiConstants.reviewCycles,
      data: {
        'name': 'Q$quarterNum $fyLabel',
        'fyLabel': fyLabel,
        'quarterNum': quarterNum,
        'startDate': _date(startDate),
        'endDate': _date(endDate),
        'selfRatingDeadline': _date(self),
        'managerReviewDeadline': _date(manager),
        'opsScoringDeadline': _date(ops),
        'financeScoringDeadline': _date(finance),
        'autoCreateOnActivate': true,
      },
    );
    final created = unwrapObject(createRes);
    final id = created['id']?.toString() ?? '';
    if (id.isNotEmpty) await _activateCycle(id);
    return id;
  }

  // Date-only wire form (yyyy-MM-dd); a full local ISO timestamp can slip a day
  // across the UTC boundary.
  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
