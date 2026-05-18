import '../../../employee/data/models/enums.dart';
import '../models/bulk_approve_request.dart';
import '../models/bulk_approve_response.dart';
import '../models/bulk_approved_item.dart';
import '../models/bulk_skipped_item.dart';
import '../models/enums.dart';
import 'bulk_approve_repository.dart';
import 'mock_manager_review_repository.dart';

/// Mock bulk-approve. Walks the manager-review mock to determine which
/// review ids are eligible (state=EMPLOYEE_SUBMITTED_ALL) and which
/// would be skipped. Reasons distribute realistically: any id with
/// `pravin` or `anita` gets `NOT_EMPLOYEE_SUBMITTED`, any id with
/// `partial` triggers `INCOMPLETE_AFTER_COPY`, the rest succeed.
class MockBulkApproveRepository implements BulkApproveRepository {
  final Duration latency;
  MockBulkApproveRepository({
    this.latency = const Duration(milliseconds: 600),
  });

  final MockManagerReviewRepository _reviewRepo =
      MockManagerReviewRepository();

  @override
  Future<BulkApproveResponse> bulkApprove(
      BulkApproveRequest request) async {
    await Future<void>.delayed(latency);
    final approved = <BulkApprovedItem>[];
    final skipped = <BulkSkippedItem>[];

    for (final id in request.reviewIds) {
      final review = await _reviewRepo.getReviewDetail(id);
      if (review.state != ReviewState.employeeSubmittedAll) {
        skipped.add(BulkSkippedItem(
          reviewId: id,
          employeeName: review.employee.name,
          employeeCode: review.employee.employeeCode,
          reason: BulkSkipReason.notEmployeeSubmitted,
          reasonCode: 'NOT_EMPLOYEE_SUBMITTED',
          detail: 'Current state: ${review.state.displayName}',
        ));
        continue;
      }
      if (id.contains('partial')) {
        skipped.add(BulkSkippedItem(
          reviewId: id,
          employeeName: review.employee.name,
          employeeCode: review.employee.employeeCode,
          reason: BulkSkipReason.incompleteAfterCopy,
          reasonCode: 'INCOMPLETE_AFTER_COPY',
          detail: 'Ops feed missing for Customer Escalations',
        ));
        continue;
      }
      // Approved — use the employee's self total as a stand-in for
      // the copied manager total. The real backend would recompute.
      approved.add(BulkApprovedItem(
        reviewId: id,
        employeeName: review.employee.name,
        employeeCode: review.employee.employeeCode,
        managerTotal: review.totals.selfTotal ?? 80.0,
      ));
    }

    return BulkApproveResponse(
      approvedCount: approved.length,
      skippedCount: skipped.length,
      approved: approved,
      skipped: skipped,
    );
  }
}
