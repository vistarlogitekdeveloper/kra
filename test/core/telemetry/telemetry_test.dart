import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/telemetry/telemetry.dart';

void main() {
  const uuid = '7f3c2a10-1b2c-4d5e-8f90-a1b2c3d4e5f6';

  test('screen names carry no record ids', () {
    expect(Telemetry.routePattern('/employee/home'), '/employee/home');
    expect(Telemetry.routePattern('/reviews/monthly?year=2026&month=9'),
        '/reviews/monthly');
    expect(Telemetry.routePattern('/employee/history/$uuid'),
        '/employee/history/:id');
    expect(Telemetry.routePattern('/manager/team/reviews/$uuid/rate/review'),
        '/manager/team/reviews/:id/rate/review');
    expect(Telemetry.routePattern('/manager/team/list/$uuid/history'),
        '/manager/team/list/:id/history');
    expect(Telemetry.routePattern('/reviews/quarterly/$uuid'),
        '/reviews/quarterly/:id');
    expect(Telemetry.routePattern('/hr/employees/$uuid/edit'),
        '/hr/employees/:id/edit');
    expect(Telemetry.routePattern('/reset-password?token=abc123&email=a@b.c'),
        '/reset-password');
    expect(
        Telemetry.routePattern(
            'https://api.example.com/api/v1/kra/reviews/monthly/$uuid/submit-stage'),
        '/api/v1/kra/reviews/monthly/:id/submit-stage');
  });

  test('organisation ids are replaced even without a digit in them', () {
    expect(
        Telemetry.routePattern(
            '/hr/organizations/org_vistar_main/rating-access?period=2026-09'),
        '/hr/organizations/:id/rating-access');
    expect(Telemetry.routePattern('/hr/organizations/$uuid/rating-access'),
        '/hr/organizations/:id/rating-access');
    expect(Telemetry.routePattern('/hr/organizations'), '/hr/organizations');
    expect(Telemetry.routePattern('/organizations/switch'),
        '/organizations/switch');
    expect(Telemetry.routePattern('/organizations/acme'), '/organizations/:id');
  });

  test('employee codes and review months become :ref', () {
    expect(Telemetry.routePattern('/employees/VST0042'), '/employees/:ref');
    expect(Telemetry.routePattern('/employees/emp-12'), '/employees/:ref');
    expect(
        Telemetry.routePattern(
            '/organizations/org_vistar_main/rating-access/2026-09/SELF_RATING'),
        '/organizations/:id/rating-access/:ref/SELF_RATING');
  });

  test('the review journey is named from successful writes', () {
    expect(Telemetry.actionFor('POST', '/employee/reviews/$uuid/self-rate'),
        'self_rating_submitted');
    expect(
        Telemetry.actionFor('PATCH', '/employee/profile'), 'profile_updated');
    expect(Telemetry.actionFor('POST', '/manager/reviews/$uuid/manager-rate'),
        'manager_rating_submitted');
    expect(Telemetry.actionFor('PATCH', '/manager/reviews/$uuid/manager-rate'),
        'manager_rating_updated');
    expect(Telemetry.actionFor('POST', '/manager/reviews/$uuid/comment'),
        'review_comment_added');
    expect(Telemetry.actionFor('POST', '/manager/reviews/bulk-approve'),
        'reviews_bulk_approved');
    expect(Telemetry.actionFor('POST', '/reviews/monthly/$uuid/submit-stage'),
        'review_stage_submitted');
    expect(Telemetry.actionFor('POST', '/reviews/monthly/$uuid/save-scores'),
        'rating_saved');
    expect(Telemetry.actionFor('POST', '/reviews/monthly/$uuid/mark-paid'),
        'incentive_marked_paid');
    expect(
        Telemetry.actionFor('POST', '/reviews/monthly/$uuid/lock-management'),
        'management_review_locked');
    expect(
        Telemetry.actionFor('POST', '/reviews/monthly/$uuid/unlock-management'),
        'management_review_unlocked');
  });

  test('HR and super admin writes are named', () {
    expect(
        Telemetry.actionFor('POST', '/kra-templates'), 'kra_template_created');
    expect(Telemetry.actionFor('PATCH', '/kra-templates/$uuid'),
        'kra_template_updated');
    expect(Telemetry.actionFor('DELETE', '/kra-templates/$uuid'),
        'kra_template_deleted');
    expect(Telemetry.actionFor('POST', '/kra-templates/$uuid/clone'),
        'kra_template_cloned');
    expect(Telemetry.actionFor('POST', '/kra-assignments'), 'kra_assigned');
    expect(Telemetry.actionFor('POST', '/kra-assignments/bulk'),
        'kras_bulk_assigned');
    expect(Telemetry.actionFor('PATCH', '/kra-assignments/$uuid'),
        'kra_assignment_updated');
    expect(
        Telemetry.actionFor('POST', '/review-cycles'), 'review_cycle_created');
    expect(Telemetry.actionFor('POST', '/review-cycles/$uuid/activate'),
        'review_cycle_activated');
    expect(Telemetry.actionFor('post', '/employees'), 'employee_created');
    expect(
        Telemetry.actionFor('PATCH', '/employees/$uuid'), 'employee_updated');
    expect(Telemetry.actionFor('DELETE', '/employees/$uuid'),
        'employee_deactivated');
    expect(Telemetry.actionFor('POST', '/employees/$uuid/transfer'),
        'employee_transferred');
    expect(Telemetry.actionFor('POST', '/employees/$uuid/set-password'),
        'employee_password_set');
    expect(Telemetry.actionFor('POST', '/locations'), 'location_created');
    expect(
        Telemetry.actionFor('PATCH', '/locations/$uuid'), 'location_updated');
    expect(
        Telemetry.actionFor('DELETE', '/locations/$uuid'), 'location_deleted');
    expect(
        Telemetry.actionFor('POST', '/organizations'), 'organization_created');
    expect(Telemetry.actionFor('POST', '/organizations/switch'),
        'organization_switched');
    expect(Telemetry.actionFor('PATCH', '/organizations/org_vistar_main'),
        'organization_updated');
    expect(
        Telemetry.actionFor('PUT',
            '/organizations/org_vistar_main/rating-access/2026-09/SELF_RATING'),
        'rating_access_override_set');
    expect(
        Telemetry.actionFor('DELETE',
            '/organizations/$uuid/rating-access/2026-09/REPORTING_MANAGER_RATING'),
        'rating_access_override_cleared');
    expect(Telemetry.actionFor('POST', '/auth/change-password'),
        'password_changed');
    expect(Telemetry.actionFor('POST', '/auth/forgot-password'),
        'password_reset_requested');
    expect(
        Telemetry.actionFor('POST', '/auth/reset-password'), 'password_reset');
  });

  test('reads, auto-save, sign-in and unknown paths are not reported', () {
    expect(Telemetry.actionFor('GET', '/reviews/monthly'), isNull);
    expect(Telemetry.actionFor('GET', '/reviews/monthly/$uuid'), isNull);
    expect(Telemetry.actionFor('GET', '/employee/dashboard'), isNull);
    expect(
        Telemetry.actionFor(
            'GET', '/organizations/$uuid/rating-access/2026-09'),
        isNull);
    // The manager rating auto-save runs every few seconds.
    expect(Telemetry.actionFor('POST', '/reviews/$uuid/scores'), isNull);
    expect(Telemetry.actionFor('POST', '/auth/login'), isNull);
    expect(Telemetry.actionFor('POST', '/auth/logout'), isNull);
    expect(Telemetry.actionFor('POST', '/auth/refresh'), isNull);
    expect(Telemetry.actionFor('DELETE', '/employee/profile'), isNull);
    expect(Telemetry.actionFor('POST', '/something-new'), isNull);
  });

  test(
      'off without ET_APP_ID and ET_WRITE_KEY (the default build); calls are safe',
      () async {
    expect(Telemetry.enabled, isFalse);
    await Telemetry.init();
    Telemetry.screen('/employee/home');
    Telemetry.track('self_rating_submitted');
    Telemetry.error('api_error', {'endpoint': '/employees', 'method': 'POST'});
    Telemetry.signedIn(userId: 'u1', role: 'HR_ADMIN');
    Telemetry.signedOut();
  });

  test('the interceptor changes nothing about a request or its outcome',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid/api/v1/kra/'))
      ..httpClientAdapter = _Answer()
      ..interceptors.add(TelemetryInterceptor());
    final ok = await dio.post<dynamic>('/kra-templates', data: {'x': 1});
    expect(ok.statusCode, 201);
    expect((ok.data as Map)['success'], isTrue);
    await expectLater(
      dio.post<dynamic>('/reviews/monthly/$uuid/submit-stage'),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 503)),
    );
  });
}

/// Answers 201 for a KRA template and 503 for anything else, with no network.
class _Answer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final created = options.path == '/kra-templates';
    return ResponseBody.fromString(
      jsonEncode({'success': created}),
      created ? 201 : 503,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
