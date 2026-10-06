import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:vistar_event_tracker/vistar_event_tracker.dart'
    show EventType, TrackerConfig, VistarEventTracker, VistarEvents;

import '../api/api_constants.dart';

/// Usage analytics for the KRA app, sent to the in-house event tracker and
/// read in the Platform Console under Analytics > Event tracker.
///
/// Off unless the build is given both:
///   --dart-define=ET_APP_ID=kra_app --dart-define=ET_WRITE_KEY=wk_...
/// (register the app in the Platform Console, Settings > Event tracker; the
/// write key only lets a client append events, so it may ship in the app).
/// Optional --dart-define=ET_BASE_URL=... sends a test build's events
/// somewhere other than the API host the app uses (by default, the host of
/// API_BASE, so a UAT build reports to UAT).
///
/// What is sent:
///   * screen views, by route pattern (ids and references replaced:
///     `/manager/team/reviews/:id/rate`, `/hr/organizations/:id/rating-access`)
///   * sign-in / sign-out; the user as `kra:<user id>`, with their role as the
///     only trait (the KRA sign-in answers with an organisation id, not a
///     code, so no organisation is sent)
///   * named actions from successful API writes (see [_actions]):
///     `self_rating_submitted`, `manager_rating_submitted`,
///     `review_stage_submitted`, `rating_saved`, `kra_assigned`, ...
///   * failed API calls (5xx or no connection), and client errors by TYPE
///     only (never the message, which can quote a server reply)
/// Never sent: request or response bodies, ratings, scores, review comments,
/// reasons, incentive amounts, employee names, codes or emails, KRA or
/// template names, organisation names, or any other record content. A write
/// is counted as the bare event name, with no properties.
///
/// NEVER IN THE WAY OF WORK. Nothing here is awaited by a screen, a rating, a
/// sign-in or a sign-out; start-up waits at most [_initBudget]; every call
/// swallows its own failures; the queue is capped at [_maxQueue] events
/// (oldest dropped) and lives in shared preferences; sending is in the
/// background with the SDK's backoff.
abstract final class Telemetry {
  static const _appId = String.fromEnvironment('ET_APP_ID');
  static const _writeKey = String.fromEnvironment('ET_WRITE_KEY');
  static const _baseUrlOverride = String.fromEnvironment('ET_BASE_URL');
  static const _appVersion = String.fromEnvironment('APP_VERSION');
  static const _initBudget = Duration(seconds: 2);
  static const _maxQueue = 200;

  static bool get enabled => _appId != '' && _writeKey != '';

  static VistarEventTracker get _t => VistarEventTracker.instance;
  static bool get _on => enabled && _t.isInitialized;

  static String? _lastScreen;
  static Future<void>? _resetting;

  static String get _origin {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    final u = Uri.parse(ApiConstants.baseUrl);
    return '${u.scheme}://${u.authority}';
  }

  /// Called by bootstrap() after the app's own error handlers are installed,
  /// so [_captureErrors] chains to them rather than being replaced by them.
  static Future<void> init() async {
    if (!enabled) return;
    try {
      await _t
          .init(TrackerConfig(
            appId: _appId,
            writeKey: _writeKey,
            baseUrl: _origin,
            appVersion: _appVersion.isEmpty ? null : _appVersion,
            maxQueueSize: _maxQueue,
            // The SDK's own error capture sends the exception message and
            // stack, and a message here can quote a server reply (a name, a
            // score, a comment). [_captureErrors] sends the type only.
            autoCaptureErrors: false,
          ))
          .timeout(_initBudget);
      _captureErrors();
    } catch (_) {
      // Analytics must never stop the app from starting.
    }
  }

  /// Client errors, by type only. Chains to whatever handled them before
  /// (bootstrap()'s handlers), so the app's own error handling is unchanged.
  static void _captureErrors() {
    if (!_on) return;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      _clientError(details.exception, fatal: false, library: details.library);
      previous?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final previousAsync = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      _clientError(error, fatal: true);
      return previousAsync?.call(error, stack) ?? false;
    };
  }

  static void _clientError(Object e, {required bool fatal, String? library}) {
    try {
      error(VistarEvents.clientError, {
        'error': e.runtimeType.toString(),
        if (library != null) 'library': library,
        'fatal': fatal,
      });
    } catch (_) {}
  }

  /// A screen, by its route pattern. Repeats are dropped.
  static void screen(String location) {
    if (!_on) return;
    final name = routePattern(location);
    if (name == _lastScreen) return;
    _lastScreen = name;
    _guard(() => _t.screen(name));
  }

  static void track(String name, [Map<String, dynamic>? properties]) {
    if (_on) _guard(() => _t.track(name, properties: properties));
  }

  static void error(String name, Map<String, dynamic> properties) {
    if (_on) {
      _guard(
          () => _t.track(name, properties: properties, type: EventType.error));
    }
  }

  static void _guard(void Function() fn) {
    try {
      fn();
    } catch (_) {
      // Analytics never surfaces as an app error.
    }
  }

  /// Fire and forget: the sign-in never waits for analytics.
  ///
  /// Called just BEFORE the auth state changes. With no sign-out in flight the
  /// SDK sets the user synchronously (before its first await), so the screen
  /// the sign-in leads to is already attributed to them.
  static void signedIn({required String userId, String? role}) {
    if (!_on || userId.isEmpty) return;
    final id = 'kra:$userId';
    final traits = <String, dynamic>{
      if (role != null && role.isNotEmpty) 'role': role,
    };
    final pending = _resetting;
    if (pending == null) {
      _identify(id, traits);
      return;
    }
    // A sign-out just before (a shared desk changing hands) resets the
    // identity; let it finish so this one is not wiped by it.
    unawaited(() async {
      try {
        await pending.timeout(const Duration(seconds: 5), onTimeout: () {});
      } catch (_) {}
      _identify(id, traits);
    }());
  }

  static void _identify(String id, Map<String, dynamic> traits) {
    try {
      unawaited(_t.identify(id, traits: traits).catchError((Object _) {}));
    } catch (_) {}
  }

  /// Fire and forget: the sign-out never waits for analytics (the SDK's reset
  /// sends what is queued first, which can take a while on a poor network).
  static void signedOut() {
    _lastScreen = null;
    if (!_on) return;
    try {
      late final Future<void> done;
      done = _t.reset().catchError((Object _) {}).whenComplete(() {
        if (identical(_resetting, done)) _resetting = null;
      });
      _resetting = done;
    } catch (_) {}
  }

  /// `/manager/team/reviews/9f3c...-.../rate?x=1` ->
  /// `/manager/team/reviews/:id/rate`.
  ///
  /// Any segment with a digit in it is replaced: numbers and uuids become
  /// `:id`; everything else with a digit (employee codes such as VST0042, a
  /// review month such as 2026-09) becomes `:ref`. The segment after
  /// `organizations` is always `:id` (bar `switch`): one live organisation id
  /// has no digit in it. The query string is dropped. An API version segment
  /// (`v1`) is kept.
  static String routePattern(String location) {
    final path = Uri.tryParse(location)?.path ?? location.split('?').first;
    var afterOrganizations = false;
    return path.split('/').map((s) {
      final orgSlot = afterOrganizations;
      afterOrganizations = s == 'organizations';
      if (s.isEmpty) return s;
      if (orgSlot && s != 'switch') return ':id';
      if (RegExp(r'^\d+$').hasMatch(s)) return ':id';
      if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-', caseSensitive: false)
          .hasMatch(s)) {
        return ':id';
      }
      if (RegExp(r'^v\d{1,2}$').hasMatch(s)) return s;
      if (RegExp(r'\d').hasMatch(s)) return ':ref';
      return s;
    }).join('/');
  }

  /// Successful API writes worth naming, by method and path (ids stripped).
  /// First match wins; anything else (reads, sign-in, the manager rating
  /// auto-save that runs every few seconds, unknown paths) is not reported.
  static final List<(String, RegExp, String)> _actions = [
    // Employee: their own rating and profile.
    (
      'POST',
      RegExp(r'^/employee/reviews/:(id|ref)/self-rate$'),
      'self_rating_submitted'
    ),
    ('PATCH', RegExp(r'^/employee/profile$'), 'profile_updated'),
    // Manager: rating the team.
    (
      'POST',
      RegExp(r'^/manager/reviews/:(id|ref)/manager-rate$'),
      'manager_rating_submitted'
    ),
    (
      'PATCH',
      RegExp(r'^/manager/reviews/:(id|ref)/manager-rate$'),
      'manager_rating_updated'
    ),
    (
      'POST',
      RegExp(r'^/manager/reviews/:(id|ref)/comment$'),
      'review_comment_added'
    ),
    (
      'POST',
      RegExp(r'^/manager/reviews/bulk-approve$'),
      'reviews_bulk_approved'
    ),
    // Monthly reviews (the five-stage pipeline).
    (
      'POST',
      RegExp(r'^/reviews/monthly/:(id|ref)/submit-stage$'),
      'review_stage_submitted'
    ),
    (
      'POST',
      RegExp(r'^/reviews/monthly/:(id|ref)/save-scores$'),
      'rating_saved'
    ),
    (
      'POST',
      RegExp(r'^/reviews/monthly/:(id|ref)/mark-paid$'),
      'incentive_marked_paid'
    ),
    (
      'POST',
      RegExp(r'^/reviews/monthly/:(id|ref)/lock-management$'),
      'management_review_locked'
    ),
    (
      'POST',
      RegExp(r'^/reviews/monthly/:(id|ref)/unlock-management$'),
      'management_review_unlocked'
    ),
    // HR: KRA templates and assignments.
    ('POST', RegExp(r'^/kra-templates$'), 'kra_template_created'),
    ('PATCH', RegExp(r'^/kra-templates/:(id|ref)$'), 'kra_template_updated'),
    ('DELETE', RegExp(r'^/kra-templates/:(id|ref)$'), 'kra_template_deleted'),
    (
      'POST',
      RegExp(r'^/kra-templates/:(id|ref)/clone$'),
      'kra_template_cloned'
    ),
    ('POST', RegExp(r'^/kra-assignments$'), 'kra_assigned'),
    ('POST', RegExp(r'^/kra-assignments/bulk$'), 'kras_bulk_assigned'),
    (
      'PATCH',
      RegExp(r'^/kra-assignments/:(id|ref)$'),
      'kra_assignment_updated'
    ),
    ('POST', RegExp(r'^/review-cycles$'), 'review_cycle_created'),
    (
      'POST',
      RegExp(r'^/review-cycles/:(id|ref)/activate$'),
      'review_cycle_activated'
    ),
    // HR: employees and locations.
    ('POST', RegExp(r'^/employees$'), 'employee_created'),
    ('PATCH', RegExp(r'^/employees/:(id|ref)$'), 'employee_updated'),
    ('DELETE', RegExp(r'^/employees/:(id|ref)$'), 'employee_deactivated'),
    (
      'POST',
      RegExp(r'^/employees/:(id|ref)/transfer$'),
      'employee_transferred'
    ),
    (
      'POST',
      RegExp(r'^/employees/:(id|ref)/set-password$'),
      'employee_password_set'
    ),
    ('POST', RegExp(r'^/locations$'), 'location_created'),
    ('PATCH', RegExp(r'^/locations/:(id|ref)$'), 'location_updated'),
    ('DELETE', RegExp(r'^/locations/:(id|ref)$'), 'location_deleted'),
    // Super admin: organisations and rating access.
    ('POST', RegExp(r'^/organizations$'), 'organization_created'),
    ('POST', RegExp(r'^/organizations/switch$'), 'organization_switched'),
    ('PATCH', RegExp(r'^/organizations/:(id|ref)$'), 'organization_updated'),
    (
      'PUT',
      RegExp(r'^/organizations/:id/rating-access/:ref/[A-Z_]+$'),
      'rating_access_override_set'
    ),
    (
      'DELETE',
      RegExp(r'^/organizations/:id/rating-access/:ref/[A-Z_]+$'),
      'rating_access_override_cleared'
    ),
    // Account.
    ('POST', RegExp(r'^/auth/change-password$'), 'password_changed'),
    ('POST', RegExp(r'^/auth/forgot-password$'), 'password_reset_requested'),
    ('POST', RegExp(r'^/auth/reset-password$'), 'password_reset'),
  ];

  /// The business event for a successful API call, or null.
  static String? actionFor(String method, String path) {
    final pattern = routePattern(path);
    for (final (m, re, name) in _actions) {
      if (m == method.toUpperCase() && re.hasMatch(pattern)) return name;
    }
    return null;
  }
}

/// Reports named actions and failed calls from the app's Dio client
/// (dioProvider). Adds no headers and changes nothing about the request or
/// its handling.
class TelemetryInterceptor extends Interceptor {
  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    // This client uses Dio's default validateStatus, so only a 2xx arrives
    // here; a 2xx whose envelope says `success: false` did not happen either.
    final code = response.statusCode ?? 0;
    if (Telemetry.enabled && code >= 200 && code < 300) {
      String? name;
      try {
        final body = response.data;
        final refused = body is Map && body['success'] == false;
        final o = response.requestOptions;
        if (!refused) name = Telemetry.actionFor(o.method, o.path);
      } catch (_) {}
      if (name != null) Telemetry.track(name);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (Telemetry.enabled) {
      try {
        final status = err.response?.statusCode;
        // A 4xx is a decision the server made, and a cancel is the app's own
        // (a request refused because the session is gone).
        if ((status == null || status >= 500) &&
            err.type != DioExceptionType.cancel) {
          Telemetry.error('api_error', {
            'endpoint': Telemetry.routePattern(err.requestOptions.path),
            'method': err.requestOptions.method,
            if (status != null) 'status': status,
            'kind': err.type.name,
          });
        }
      } catch (_) {}
    }
    handler.next(err);
  }
}
