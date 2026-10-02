import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/api_error.dart';
import '../../../../core/api/envelope.dart';
import '../models/monthly_review.dart';
import '../models/rating_access.dart';
import '../models/review_stage.dart';

/// When each rating stage of a month accepts entries, per organisation, and
/// the super admin's overrides of it (docs/RATING_ACCESS.md §3.5).
///
/// SUPER_ADMIN only, and the organisation travels in the PATH rather than the
/// token claim: a switched super admin's claim reverts to their home
/// organisation on the next token refresh, so the claim cannot be trusted to
/// name the organisation being administered.
///
/// A backend without the feature answers 404 RES_001 on every call; callers
/// treat that as "not deployed yet", not as a bug.
abstract class RatingAccessRepository {
  /// All five rating stages of [period] for [organizationId].
  Future<RatingAccessMonth> fetchMonth(
    String organizationId,
    ReviewPeriod period,
  );

  /// Every override the organisation holds, newest `updatedAt` first.
  Future<List<RatingAccessOverride>> fetchOverrides(String organizationId);

  /// Creates or replaces the override for one stage of one month, and returns
  /// the month as it now resolves.
  ///
  /// [openUntilDate] is `YYYY-MM-DD` and means the END of that day, IST; null
  /// means no end. It is sent for [RatingAccessMode.open] only — the server
  /// refuses one alongside CLOSED. [reason] is trimmed and dropped when blank.
  Future<RatingAccessMonth> setOverride(
    String organizationId,
    ReviewPeriod period,
    ReviewStage stage, {
    required RatingAccessMode mode,
    String? openUntilDate,
    String? reason,
  });

  /// Removes the override, putting the stage back on its deadline. Idempotent.
  Future<RatingAccessMonth> clearOverride(
    String organizationId,
    ReviewPeriod period,
    ReviewStage stage,
  );
}

class ApiRatingAccessRepository implements RatingAccessRepository {
  final Dio _dio;
  ApiRatingAccessRepository({required Dio dio}) : _dio = dio;

  // Every segment is encoded: an organisation id is caller data, and an
  // unencoded '/' or '?' in it would address a different route.
  String _root(String organizationId) =>
      '${ApiConstants.organizations}/${Uri.encodeComponent(organizationId)}'
      '/${ApiConstants.ratingAccess}';

  String _monthPath(String organizationId, ReviewPeriod period) =>
      '${_root(organizationId)}/${Uri.encodeComponent(period.key)}';

  String _stagePath(
    String organizationId,
    ReviewPeriod period,
    ReviewStage stage,
  ) =>
      '${_monthPath(organizationId, period)}'
      '/${Uri.encodeComponent(stage.toApiString())}';

  @override
  Future<RatingAccessMonth> fetchMonth(
    String organizationId,
    ReviewPeriod period,
  ) async {
    try {
      final response = await _dio.get(_monthPath(organizationId, period));
      return _month(response, organizationId, period);
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<List<RatingAccessOverride>> fetchOverrides(
    String organizationId,
  ) async {
    try {
      final response = await _dio.get(
        '${_root(organizationId)}/${ApiConstants.ratingAccessOverrides}',
      );
      final overrides = _overrideList(response)
          .map(RatingAccessOverride.fromJson)
          .whereType<RatingAccessOverride>()
          .toList();
      // The server already sorts; sorting again keeps the order a property of
      // this method rather than of whichever backend answered.
      return overrides..sort(RatingAccessOverride.newestFirst);
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<RatingAccessMonth> setOverride(
    String organizationId,
    ReviewPeriod period,
    ReviewStage stage, {
    required RatingAccessMode mode,
    String? openUntilDate,
    String? reason,
  }) async {
    final until = openUntilDate?.trim();
    final note = reason?.trim();
    final body = <String, dynamic>{
      'mode': mode.toApiString(),
      // Explicit null for an open-ended reopen; absent for CLOSED.
      if (mode == RatingAccessMode.open)
        'openUntilDate': (until == null || until.isEmpty) ? null : until,
      if (note != null && note.isNotEmpty) 'reason': note,
    };
    try {
      final response = await _dio.put(
        _stagePath(organizationId, period, stage),
        data: body,
      );
      return _month(response, organizationId, period);
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<RatingAccessMonth> clearOverride(
    String organizationId,
    ReviewPeriod period,
    ReviewStage stage,
  ) async {
    try {
      final response =
          await _dio.delete(_stagePath(organizationId, period, stage));
      return _month(response, organizationId, period);
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  RatingAccessMonth _month(
    Response response,
    String organizationId,
    ReviewPeriod period,
  ) {
    final month = RatingAccessMonth.fromJson(
      unwrapObject(response),
      fallbackOrganizationId: organizationId,
      fallbackPeriod: period,
    );
    if (month != null) return month;
    throw const ApiError(
      type: ApiErrorType.unknown,
      code: 'BAD_RESPONSE',
      message: 'Unexpected response from the server. Please try again.',
    );
  }

  /// The contract's bare list, or the same list nested as `data.overrides`,
  /// so a paginated reshuffle of the endpoint does not empty the history.
  List<dynamic> _overrideList(Response response) {
    final body = response.data;
    if (body case {'success': true, 'data': {'overrides': final List list}}) {
      return list;
    }
    return unwrapList(response);
  }
}
