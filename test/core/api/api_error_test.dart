import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';

/// Locks the backend `error.details` → `ApiError.fieldErrors` mapping. The
/// real motivator: a generic "Validation failed" banner gave HR users no way
/// to know which field they got wrong (e.g. `selfRatingDeadline must be on
/// or after endDate`). The details map preserves that hint, and
/// [ApiError.combinedMessage] flattens it for a banner.
void main() {
  group('ApiError.fromDioException — error.details parsing', () {
    test('promotes a field-keyed details map to fieldErrors', () {
      final err = ApiError.fromDioException(_validationException({
        'success': false,
        'error': {
          'code': 'VAL_001',
          'message': 'Validation failed',
          'details': {
            'selfRatingDeadline': [
              'selfRatingDeadline must be on or after endDate',
            ],
            'opsScoringDeadline': [
              'opsScoringDeadline must be on or after managerReviewDeadline',
            ],
          },
        },
      }));

      expect(err.type, ApiErrorType.validation);
      expect(err.fieldErrors.keys,
          containsAll(['selfRatingDeadline', 'opsScoringDeadline']));
      expect(err.fieldErrors['selfRatingDeadline'],
          ['selfRatingDeadline must be on or after endDate']);
    });

    test('combinedMessage flattens field errors for a banner', () {
      final err = ApiError.fromDioException(_validationException({
        'success': false,
        'error': {
          'code': 'VAL_001',
          'message': 'Validation failed',
          'details': {
            'selfRatingDeadline': ['must be on or after endDate'],
          },
        },
      }));

      expect(err.combinedMessage, 'must be on or after endDate');
    });

    test('combinedMessage falls back to message when details is absent', () {
      final err = ApiError.fromDioException(_validationException({
        'success': false,
        'error': {'code': 'VAL_001', 'message': 'Validation failed'},
      }));

      expect(err.fieldErrors, isEmpty);
      expect(err.combinedMessage, err.message);
    });

    test('tolerates a string value instead of a list', () {
      final err = ApiError.fromDioException(_validationException({
        'success': false,
        'error': {
          'code': 'VAL_001',
          'message': 'Validation failed',
          'details': {'name': 'name is required'},
        },
      }));

      expect(err.fieldErrors['name'], ['name is required']);
    });

    test('silently drops a malformed details payload', () {
      final err = ApiError.fromDioException(_validationException({
        'success': false,
        'error': {
          'code': 'VAL_001',
          'message': 'Validation failed',
          'details': 'oops — not a map',
        },
      }));

      expect(err.fieldErrors, isEmpty);
      expect(err.message, isNotEmpty);
    });
  });
}

DioException _validationException(Map<String, dynamic> body) {
  final req = RequestOptions(path: '/review-cycles');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: req,
      statusCode: 400,
      data: body,
    ),
  );
}
