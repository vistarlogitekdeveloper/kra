// The list endpoint (GET /employee/reviews) returns the full review
// shape including `rows[]` and `monthlyScores[]` — there is no
// thinner "summary" projection on the backend. Carrying two model
// types would just shed data on parse, so this file aliases the
// canonical shape and keeps the original spec'd file structure.
//
// History list rendering uses only the top-level fields
// (state, finalAvg*, payableIncentive, reviewCycle.name) — the
// per-row data is ignored unless the user drills into the detail.

import 'my_review_detail.dart';

export 'my_review_detail.dart' show MyReview, ReviewCycleRef, ReviewMonthRef;

typedef MyReviewSummary = MyReview;

/// Lightweight pagination wrapper used by the history list controller.
/// `total` falls back to the list length when the backend hasn't yet
/// supplied a meta block, so [hasMore] resolves to `false` rather
/// than perpetually-true.
class MyReviewPage {
  final List<MyReviewSummary> reviews;
  final int page;
  final int pageSize;
  final int total;

  const MyReviewPage({
    required this.reviews,
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
  });

  bool get hasMore => reviews.length + ((page - 1) * pageSize) < total;

  MyReviewPage copyWith({
    List<MyReviewSummary>? reviews,
    int? page,
    int? pageSize,
    int? total,
  }) {
    return MyReviewPage(
      reviews: reviews ?? this.reviews,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      total: total ?? this.total,
    );
  }
}
