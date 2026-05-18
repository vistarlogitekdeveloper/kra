import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/api_error.dart';
import '../../../../core/api/envelope.dart';
import '../models/bulk_approve_request.dart';
import '../models/bulk_approve_response.dart';
import 'bulk_approve_repository.dart';

class ApiBulkApproveRepository implements BulkApproveRepository {
  /// Hard cap per the API spec. The UI also enforces this at the
  /// multi-select chip count, but a second guard here means a
  /// programmatic caller can't ship a 51-id list past us by mistake.
  static const int _maxIdsPerCall = 50;

  final Dio _dio;
  ApiBulkApproveRepository({required Dio dio}) : _dio = dio;

  @override
  Future<BulkApproveResponse> bulkApprove(BulkApproveRequest request) async {
    if (request.reviewIds.length > _maxIdsPerCall) {
      throw const ApiError(
        type: ApiErrorType.unknown,
        code: 'TOO_MANY_REVIEWS',
        message:
            'Bulk approve accepts at most $_maxIdsPerCall reviews at a time.',
      );
    }
    try {
      final response = await _dio.post(
        ApiConstants.managerBulkApprove,
        data: request.toJson(),
      );
      return BulkApproveResponse.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
