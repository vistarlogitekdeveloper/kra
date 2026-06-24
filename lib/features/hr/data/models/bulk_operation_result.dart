/// Result of a client-side bulk operation that fans out N requests to a
/// per-row endpoint (e.g. "delete every employee" → N × DELETE
/// `/employees/:id`). The backend doesn't expose bulk endpoints for the
/// admin-tools surfaces, so the orchestration happens here and we report
/// how many rows succeeded vs failed so the UI can show an honest summary
/// rather than a misleading "all done!" when some rows quietly failed.
class BulkOperationResult {
  /// Number of rows that succeeded — i.e. the per-row call returned 2xx.
  final int successCount;

  /// Number of rows that errored. Each failure also has a short label in
  /// [failures] so the UI can show a "Failed: emp-12, emp-39" line
  /// without grossing the user out with a stacktrace.
  final int failureCount;

  /// Display labels (employee name, cycle name) of rows that failed —
  /// capped at the first ~5 to keep the snackbar / dialog readable.
  final List<String> failures;

  const BulkOperationResult({
    required this.successCount,
    required this.failureCount,
    required this.failures,
  });

  int get totalAttempted => successCount + failureCount;
  bool get isFullyClean => failureCount == 0;
}
