import '../../../../core/api/json_parse.dart';
import '../../../employee/data/models/enums.dart';
import 'review_totals.dart';
import 'transition_error.dart';

/// Response shape for POST /manager/reviews/:reviewId/manager-rate.
///
/// The critical field is [transitioned] — scores are persisted
/// regardless, but the state only progresses to MANAGER_RATED_ALL
/// when every required source has filled their part. If
/// `transitioned == false`, [transitionError] explains why and the
/// UI routes to the partial-success screen instead of the success
/// screen.
class ManagerRateResponse {
  final ReviewState state;
  final ReviewTotals totals;

  /// `true` if the state moved forward (typically to
  /// MANAGER_RATED_ALL). `false` means scores were saved but the
  /// state stayed put — render the "partial" path.
  final bool transitioned;
  final TransitionError? transitionError;

  const ManagerRateResponse({
    required this.state,
    required this.totals,
    required this.transitioned,
    this.transitionError,
  });

  factory ManagerRateResponse.fromJson(Map<String, dynamic> json) =>
      ManagerRateResponse(
        state: ReviewState.fromApi(
            JsonParse.parseString(json['state']) ?? 'DRAFT'),
        totals: ReviewTotals.fromJson(
            JsonParse.parseMap(json['totals']) ?? const {}),
        transitioned: JsonParse.parseBool(json['transitioned']) ?? false,
        transitionError:
            JsonParse.parseMap(json['transitionError']) == null
                ? null
                : TransitionError.fromJson(
                    JsonParse.parseMap(json['transitionError'])!),
      );

  Map<String, dynamic> toJson() => {
        'state': state.toApiString(),
        'totals': totals.toJson(),
        'transitioned': transitioned,
        'transitionError': transitionError?.toJson(),
      };
}
