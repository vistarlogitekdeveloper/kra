import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../models/review_stage.dart';

/// Reads the deadline schedule the BACKEND is actually running.
///
/// The days are a published business rule, but each backend instance can
/// override them with `KRA_*_DEADLINE_DAY` env vars, and its startup log states
/// that the app follows whatever `GET /config/deadlines` returns. So the app
/// reads it — otherwise an override moves the reminder emails while every
/// screen keeps counting to the frozen table, which is exactly the drift that
/// had HR and Accounts being told the 13th while the emails chased the 12th.
///
/// Best-effort by design: the endpoint is young, so an older backend answers
/// 404, and boot may run offline. Every failure leaves the published table in
/// place rather than surfacing an error, because a deadline the user cannot see
/// is worse than one that is a day stale on a misconfigured instance.
abstract class DeadlineScheduleRepository {
  /// The server's schedule, or null when it could not be read.
  Future<Map<ReviewStage, int>?> fetch();
}

class ApiDeadlineScheduleRepository implements DeadlineScheduleRepository {
  final Dio _dio;
  ApiDeadlineScheduleRepository({required Dio dio}) : _dio = dio;

  @override
  Future<Map<ReviewStage, int>?> fetch() async {
    try {
      final response = await _dio.get(
        ApiConstants.configDeadlines,
        // Unauthenticated: the endpoint is mounted ahead of the auth middleware
        // so the schedule can be read before anyone signs in.
        options: Options(extra: const {'skipAuth': true}),
      );
      final data = unwrapObject(response);
      final raw = data['deadlines'];
      if (raw is! Map) return null;

      // EXACT wire names only. `ReviewStage.fromApi` deliberately pins anything
      // it does not recognise to `selfRating` so a stray stage cannot take out a
      // dashboard — helpful there, silently wrong here, where it would file an
      // unknown key's day under Self-Rating and move a real deadline.
      final byWireName = {
        for (final stage in ReviewStage.values) stage.toApiString(): stage,
      };

      final parsed = <ReviewStage, int>{};
      raw.forEach((key, value) {
        final stage = byWireName[key.toString().trim().toUpperCase()];
        final day = value is num ? value.toInt() : int.tryParse('$value');
        // A stage we do not know is skipped, not fatal: a backend that adds one
        // must not cost us the days we do understand.
        if (stage != null && day != null) parsed[stage] = day;
      });
      return parsed.isEmpty ? null : parsed;
    } catch (_) {
      // Offline, a 404 from an older backend, a cold start that timed out —
      // all mean the same thing here: keep the published table.
      return null;
    }
  }
}
