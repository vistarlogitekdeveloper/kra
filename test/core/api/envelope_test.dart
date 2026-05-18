import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/api/envelope.dart';

void main() {
  group('unwrapObject', () {
    test('returns data map from success envelope', () {
      final response = _fakeResponse({'success': true, 'data': {'id': '1'}});
      expect(unwrapObject(response), {'id': '1'});
    });

    test('throws ApiError on success: false', () {
      final response = _fakeResponse({
        'success': false,
        'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
      });
      expect(
        () => unwrapObject(response),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'NOT_FOUND')),
      );
    });

    test('throws on non-map data', () {
      final response = _fakeResponse({'success': true, 'data': [1, 2, 3]});
      expect(() => unwrapObject(response), throwsA(isA<ApiError>()));
    });
  });

  group('unwrapList', () {
    test('returns list from data array', () {
      final response = _fakeResponse({
        'success': true,
        'data': [
          {'id': '1'}
        ]
      });
      expect(unwrapList(response), hasLength(1));
    });

    test('returns list nested under items key', () {
      final response = _fakeResponse({
        'success': true,
        'data': {
          'items': [
            {'id': '1'},
            {'id': '2'}
          ]
        }
      });
      expect(unwrapList(response), hasLength(2));
    });

    test('returns list nested under employees key', () {
      final response = _fakeResponse({
        'success': true,
        'data': {
          'employees': [
            {'id': 'e1'}
          ]
        }
      });
      expect(unwrapList(response), hasLength(1));
    });
  });

  group('unwrapPaged', () {
    test('returns data map directly when data is a map', () {
      final response = _fakeResponse({
        'success': true,
        'data': {'items': [], 'page': 2, 'pageSize': 20, 'total': 100},
      });
      final result = unwrapPaged(response);
      expect(result['page'], 2);
      expect(result['total'], 100);
    });

    test('merges top-level meta into map data', () {
      final response = _fakeResponse({
        'success': true,
        'data': {'items': []},
        'meta': {'page': 3, 'limit': 10, 'total': 50, 'totalPages': 5},
      });
      final result = unwrapPaged(response);
      expect(result['page'], 3);
      expect(result['pageSize'], 10);
      expect(result['total'], 50);
      expect(result['totalPages'], 5);
    });

    test('synthesises paged envelope from bare list + meta', () {
      final response = _fakeResponse({
        'success': true,
        'data': [
          {'id': '1'},
          {'id': '2'}
        ],
        'meta': {'page': 1, 'limit': 20, 'total': 42, 'totalPages': 3},
      });
      final result = unwrapPaged(response);
      expect(result['items'], hasLength(2));
      expect(result['page'], 1);
      expect(result['pageSize'], 20);
      expect(result['total'], 42);
      expect(result['totalPages'], 3);
    });

    test('synthesises single-page from bare list with no meta', () {
      final response = _fakeResponse({
        'success': true,
        'data': [
          {'id': '1'}
        ],
      });
      final result = unwrapPaged(response);
      expect(result['items'], hasLength(1));
      expect(result['page'], 1);
      expect(result['total'], 1);
      expect(result['totalPages'], 1);
    });

    test('calculates totalPages from total / pageSize', () {
      final response = _fakeResponse({
        'success': true,
        'data': [],
        'meta': {'page': 1, 'limit': 10, 'total': 25},
      });
      final result = unwrapPaged(response);
      expect(result['totalPages'], 3); // ceil(25/10)
    });
  });

  group('rethrowAsApiError', () {
    test('rethrows ApiError unchanged', () {
      const original = ApiError(
        type: ApiErrorType.unknown,
        code: 'TEST',
        message: 'test error',
      );
      expect(
        () => rethrowAsApiError(original, StackTrace.current),
        throwsA(same(original)),
      );
    });

    test('wraps DioException into ApiError', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(
        () => rethrowAsApiError(dioErr, StackTrace.current),
        throwsA(isA<ApiError>()),
      );
    });

    test('wraps unknown errors into generic ApiError', () {
      expect(
        () => rethrowAsApiError(
            Exception('random'), StackTrace.current),
        throwsA(isA<ApiError>().having(
          (e) => e.code,
          'code',
          'UNKNOWN',
        )),
      );
    });
  });
}

Response<dynamic> _fakeResponse(Map<String, dynamic> body) {
  return Response(
    requestOptions: RequestOptions(path: '/test'),
    data: body,
    statusCode: 200,
  );
}
