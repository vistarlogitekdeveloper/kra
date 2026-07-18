import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';

/// `ApiError.isNoDirectReports` is the single gate that keeps a manager with
/// zero direct reports out of a raw-403 screen. The backend delivers the
/// sentinel inconsistently (sometimes `error.code`, sometimes `error.message`),
/// and a 403 has no dedicated ApiError branch — so this must match the marker
/// in code / message / technicalMessage, but ONLY on a real 403.
void main() {
  group('ApiError.isNoDirectReports', () {
    ApiError make({
      String code = 'VALIDATION_ERROR',
      String message = 'Something',
      String? technicalMessage,
      int? statusCode = 403,
    }) =>
        ApiError(
          type: ApiErrorType.validation,
          code: code,
          message: message,
          technicalMessage: technicalMessage,
          statusCode: statusCode,
        );

    test('true when the sentinel is in the code', () {
      expect(make(code: 'NO_DIRECT_REPORTS').isNoDirectReports, isTrue);
    });

    test('true when the sentinel is in the message (code generic)', () {
      expect(
        make(code: 'FORBIDDEN', message: 'NO_DIRECT_REPORTS').isNoDirectReports,
        isTrue,
      );
    });

    test('true when the sentinel is in the technicalMessage', () {
      expect(
        make(message: 'You are not allowed', technicalMessage: 'NOT_A_MANAGER')
            .isNoDirectReports,
        isTrue,
      );
    });

    test('true for NOT_A_MANAGER as well as NO_DIRECT_REPORTS', () {
      expect(make(code: 'NOT_A_MANAGER').isNoDirectReports, isTrue);
    });

    test('false when status is not 403 even if the marker is present', () {
      expect(
        make(code: 'NO_DIRECT_REPORTS', statusCode: 401).isNoDirectReports,
        isFalse,
      );
      expect(
        make(code: 'NO_DIRECT_REPORTS', statusCode: null).isNoDirectReports,
        isFalse,
      );
    });

    test('false for an unrelated 403', () {
      expect(
        make(code: 'FORBIDDEN', message: 'You cannot do that')
            .isNoDirectReports,
        isFalse,
      );
    });

    test('flows through ApiError.fromDioException on a real 403 response', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/manager/team'),
        response: Response(
          requestOptions: RequestOptions(path: '/manager/team'),
          statusCode: 403,
          data: {
            'success': false,
            'error': {'code': 'FORBIDDEN', 'message': 'NO_DIRECT_REPORTS'},
          },
        ),
        type: DioExceptionType.badResponse,
      );
      final apiError = ApiError.fromDioException(err);
      expect(apiError.statusCode, 403);
      expect(apiError.isNoDirectReports, isTrue);
    });
  });
}
