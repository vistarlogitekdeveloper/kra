import 'package:flutter/foundation.dart';

import '../../../../reviews/data/models/monthly_review.dart';
import '../../../../reviews/data/models/rating_access.dart';

/// A control used on one stage of a loaded month.
typedef RatingAccessStageAction = void Function(
  RatingAccessMonth month,
  RatingAccessStage stage,
);

/// What the rating-access screen does when its controls are used.
///
/// The screen owns the busy state, the confirmations and the snackbars; the
/// widgets only report which control was used, on which month and stage.
@immutable
class RatingAccessHandlers {
  final ValueChanged<ReviewPeriod> onSelectPeriod;
  final RatingAccessStageAction onOpenUntil;
  final RatingAccessStageAction onClose;
  final RatingAccessStageAction onUseDeadline;
  final ValueChanged<RatingAccessMonth> onOpenAll;
  final ValueChanged<RatingAccessMonth> onResetAll;
  final VoidCallback onRetryMonth;
  final VoidCallback onRetryHistory;

  const RatingAccessHandlers({
    required this.onSelectPeriod,
    required this.onOpenUntil,
    required this.onClose,
    required this.onUseDeadline,
    required this.onOpenAll,
    required this.onResetAll,
    required this.onRetryMonth,
    required this.onRetryHistory,
  });
}
