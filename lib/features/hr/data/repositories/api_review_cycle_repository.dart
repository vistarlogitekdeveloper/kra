import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../models/bulk_operation_result.dart';
import '../models/review_cycle.dart';
import '../../../../core/api/envelope.dart';
import 'review_cycle_repository.dart';

class ApiReviewCycleRepository implements ReviewCycleRepository {
  final Dio _dio;
  ApiReviewCycleRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<ReviewCycle>> list({ReviewCycleStatus? status}) async {
    try {
      final response = await _dio.get(
        ApiConstants.reviewCycles,
        queryParameters: {
          if (status != null) 'status': status.toApiString(),
        },
      );
      return unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(ReviewCycle.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ReviewCycle> getById(String id) async {
    try {
      final response = await _dio.get('${ApiConstants.reviewCycles}/$id');
      return ReviewCycle.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ReviewCycle> create({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    DateTime? selfRatingDeadline,
    DateTime? managerReviewDeadline,
    DateTime? opsScoringDeadline,
    DateTime? financeScoringDeadline,
  }) async {
    // Backend requires `fyLabel`, `quarterNum`, and all four deadline fields
    // (its Zod schema marks them required, contrary to the early API spec).
    // We derive fyLabel/quarter from startDate (Indian FY: Apr → Mar) and
    // default any missing deadline from endDate, matching the offsets the
    // backend seeds its own auto-created cycles with (+15, +31, +46, +62).
    final fyLabel = _indianFyLabel(startDate);
    final quarter = _indianQuarter(startDate);
    final self = selfRatingDeadline ?? endDate.add(const Duration(days: 15));
    final mgr =
        managerReviewDeadline ?? endDate.add(const Duration(days: 31));
    final ops = opsScoringDeadline ?? endDate.add(const Duration(days: 46));
    final fin =
        financeScoringDeadline ?? endDate.add(const Duration(days: 62));

    try {
      final response = await _dio.post(
        ApiConstants.reviewCycles,
        data: {
          'name': name,
          'fyLabel': fyLabel,
          'quarterNum': quarter,
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
          'selfRatingDeadline': self.toIso8601String(),
          'managerReviewDeadline': mgr.toIso8601String(),
          'opsScoringDeadline': ops.toIso8601String(),
          'financeScoringDeadline': fin.toIso8601String(),
        },
      );
      return ReviewCycle.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  /// Indian financial year label for a date — e.g. 2026-05-12 → "FY26-27",
  /// 2027-01-15 → "FY26-27". FY starts in April.
  static String _indianFyLabel(DateTime d) {
    final startYear = d.month >= 4 ? d.year : d.year - 1;
    final endYear = startYear + 1;
    String two(int y) => (y % 100).toString().padLeft(2, '0');
    return 'FY${two(startYear)}-${two(endYear)}';
  }

  /// Indian FY quarter (1–4) for a date. Apr–Jun=1, Jul–Sep=2, Oct–Dec=3,
  /// Jan–Mar=4.
  static int _indianQuarter(DateTime d) {
    if (d.month >= 4 && d.month <= 6) return 1;
    if (d.month >= 7 && d.month <= 9) return 2;
    if (d.month >= 10 && d.month <= 12) return 3;
    return 4;
  }

  @override
  Future<ReviewCycle> update(String id, Map<String, dynamic> changes) async {
    try {
      final response = await _dio.patch(
        '${ApiConstants.reviewCycles}/$id',
        data: changes,
      );
      return ReviewCycle.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ReviewCycle> activate(String id) async {
    try {
      final response =
          await _dio.post('${ApiConstants.reviewCycles}/$id/activate');
      return ReviewCycle.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ReviewCycle> close(String id) async {
    try {
      final response =
          await _dio.post('${ApiConstants.reviewCycles}/$id/close');
      return ReviewCycle.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _dio.delete('${ApiConstants.reviewCycles}/$id');
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<BulkOperationResult> deleteAll() async {
    final cycles = await list();
    int ok = 0;
    int bad = 0;
    final failures = <String>[];
    for (final c in cycles) {
      try {
        await delete(c.id);
        ok += 1;
      } catch (_) {
        bad += 1;
        if (failures.length < 5) failures.add(c.name);
      }
    }
    return BulkOperationResult(
      successCount: ok,
      failureCount: bad,
      failures: failures,
    );
  }
}
