import '../models/bulk_approve_request.dart';
import '../models/bulk_approve_response.dart';

/// Contract for the bulk-approve flow.
///
/// Caller is responsible for keeping `reviewIds.length <= 50` per the
/// API contract — the implementation enforces it client-side as a
/// belt-and-suspenders guard. Returns even on partial-skip success
/// (the backend reports skips via the response payload, not HTTP).
abstract class BulkApproveRepository {
  Future<BulkApproveResponse> bulkApprove(BulkApproveRequest request);
}
