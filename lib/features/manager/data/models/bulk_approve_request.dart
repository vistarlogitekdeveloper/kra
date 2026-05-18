/// Wire payload for POST /manager/reviews/bulk-approve.
///
/// Max 50 review ids per call per the spec — enforced at the
/// repository so the UI doesn't accidentally trigger a 400 by passing
/// too many. Callers should chunk the selection client-side if they
/// have more than 50.
class BulkApproveRequest {
  /// Reviews to copy-and-approve. Only EMPLOYEE_SUBMITTED_ALL rows
  /// are valid candidates — the backend rejects the rest with a
  /// `NOT_EMPLOYEE_SUBMITTED` skip reason.
  final List<String> reviewIds;

  /// Optional comment applied to every approved review.
  final String? comment;

  const BulkApproveRequest({
    required this.reviewIds,
    this.comment,
  });

  Map<String, dynamic> toJson() => {
        'reviewIds': reviewIds,
        if (comment != null && comment!.trim().isNotEmpty)
          'comment': comment!.trim(),
      };
}
