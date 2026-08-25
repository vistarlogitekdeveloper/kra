import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/repositories/api_kra_template_repository.dart';

/// Guards the CLONE request body.
///
/// Duplicating a template returned `400 VAL_001 {"name": ["Invalid input:
/// expected string, received undefined"]}` for every template: the client
/// posted to `/kra-templates/:id/clone` with **no body at all**, while the
/// endpoint's schema is `{ name: string().min(1).max(200), role?: string }`.
/// Clone was dead on arrival, and nothing here noticed because no test looked
/// at what was actually sent.
void main() {
  /// Records the outgoing request and replies with a success envelope.
  ///
  /// A hand-rolled adapter rather than a mocking package — this project has no
  /// HTTP test dependency, and capturing `RequestOptions.data` is all that is
  /// needed to assert a payload.
  late RequestOptions captured;

  Dio dioReturning(Map<String, dynamic> data) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1/kra'));
    dio.httpClientAdapter = _RecordingAdapter(
      onRequest: (options) => captured = options,
      body: {'success': true, 'data': data},
    );
    return dio;
  }

  Map<String, dynamic> templateJson() => {
        'id': 'new-id',
        'name': 'Site Manager (Copy)',
        'role': 'MANAGER',
        'isActive': true,
      };

  test('the name is sent — the field whose absence made every clone a 400',
      () async {
    final repo = ApiKraTemplateRepository(dio: dioReturning(templateJson()));

    await repo.clone('tpl-1', name: 'Site Manager (Copy)');

    expect(captured.method, 'POST');
    expect(captured.path, '/kra-templates/tpl-1/clone');
    expect(captured.data, isA<Map>());
    expect((captured.data as Map)['name'], 'Site Manager (Copy)');
  });

  test('role is OMITTED when not given, so the API copies the source role',
      () async {
    final repo = ApiKraTemplateRepository(dio: dioReturning(templateJson()));

    await repo.clone('tpl-1', name: 'Copy');

    // Sending role: null would fail the optional-string schema; leaving the key
    // out is what makes the clone inherit the source template's role.
    expect((captured.data as Map).containsKey('role'), isFalse);
  });

  test('an explicit role is passed through', () async {
    final repo = ApiKraTemplateRepository(dio: dioReturning(templateJson()));

    await repo.clone('tpl-1', name: 'Copy', role: 'BD_MANAGER');

    expect((captured.data as Map)['role'], 'BD_MANAGER');
  });

  test('an empty role string is treated as absent, not sent as ""', () async {
    // The schema is min(1); "" would be a 400.
    final repo = ApiKraTemplateRepository(dio: dioReturning(templateJson()));

    await repo.clone('tpl-1', name: 'Copy', role: '');

    expect((captured.data as Map).containsKey('role'), isFalse);
  });

  test('the created template is parsed back out of the envelope', () async {
    final repo = ApiKraTemplateRepository(dio: dioReturning(templateJson()));

    final cloned = await repo.clone('tpl-1', name: 'Site Manager (Copy)');

    expect(cloned.id, 'new-id');
    expect(cloned.name, 'Site Manager (Copy)');
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  final void Function(RequestOptions) onRequest;
  final Map<String, dynamic> body;
  _RecordingAdapter({required this.onRequest, required this.body});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onRequest(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
