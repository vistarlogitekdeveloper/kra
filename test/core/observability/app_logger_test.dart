import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/observability/app_logger.dart';

/// The log scrubber, and the level gate.
///
/// Both exist because `debugPrint` is NOT stripped from release builds — it
/// writes to the platform log there exactly as in debug. So every
/// `debugPrint('parse failed: $e')` shipped whatever the exception's
/// `toString()` carried, and for a Dio error that is the request path, the
/// status line and often a body fragment.
///
/// A redaction rule nobody tests is a rule that quietly stops working the first
/// time someone reorders the list. These pin the patterns against realistic
/// inputs — real exception strings, not toy ones.
void main() {
  group('scrub removes credentials', () {
    test('a JWT goes entirely, not just its middle segment', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1MSIsInJvbGUiOiJIUiJ9'
          '.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final out = AppLog.scrub('token expired: $jwt');
      expect(out.contains('[jwt]'), isTrue);
      expect(out.contains('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'), isFalse,
          reason: 'the header segment is still a disclosure');
      expect(
          out.contains('dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk'), isFalse,
          reason: 'the signature must not survive either');
    });

    test('an Authorization header value goes', () {
      final out = AppLog.scrub('headers: {Authorization: Bearer abc123def456}');
      expect(out.contains('abc123def456'), isFalse);
      expect(out.contains('[token]'), isTrue);
    });

    test('tokens and passwords in a JSON body go', () {
      final out = AppLog.scrub(
        '{"email":"x@y.test","password":"Vistar@123",'
        '"refreshToken":"rt_9f8a7b6c5d"}',
      );
      expect(out.contains('Vistar@123'), isFalse);
      expect(out.contains('rt_9f8a7b6c5d'), isFalse);
      expect(out.contains('[redacted]'), isTrue);
    });

    test('the key name survives so the log still says WHAT was redacted', () {
      // Redacting the key as well leaves an unreadable log, which is how
      // scrubbers get switched off.
      final out = AppLog.scrub('{"password":"hunter2"}');
      expect(out.toLowerCase().contains('password'), isTrue);
      expect(out.contains('hunter2'), isFalse);
    });
  });

  group('scrub removes PII', () {
    test('an email address goes', () {
      final out = AppLog.scrub('login failed for hr.admin@vistar.test');
      expect(out.contains('hr.admin@vistar.test'), isFalse);
      expect(out.contains('[email]'), isTrue);
    });

    test('a query string goes — the standard forbids full URLs with params',
        () {
      final out = AppLog.scrub(
        'GET /reviews/monthly?year=2026&month=7&employeeId=abc failed',
      );
      expect(out.contains('employeeId=abc'), isFalse);
      expect(out.contains('[query]'), isTrue);
      expect(out.contains('/reviews/monthly'), isTrue,
          reason: 'the path is what makes the log useful; keep it');
    });

    test('a long digit run goes', () {
      final out = AppLog.scrub('employee 9876543210 not found');
      expect(out.contains('9876543210'), isFalse);
      expect(out.contains('[number]'), isTrue);
    });

    test('short numbers are LEFT ALONE', () {
      // Over-redaction that eats status codes and month numbers makes logs
      // useless, which is its own failure mode.
      final out = AppLog.scrub('status 404 for month 7 of 2026');
      expect(out.contains('404'), isTrue);
      expect(out.contains('month 7'), isTrue);
    });
  });

  group('scrub is applied on the way OUT, in every build mode', () {
    test('a message reaching the sink is already scrubbed', () {
      final captured = <String>[];
      final originalSink = AppLog.sink;
      final originalLevel = AppLog.minimumLevel;
      addTearDown(() {
        AppLog.sink = originalSink;
        AppLog.minimumLevel = originalLevel;
      });

      AppLog.minimumLevel = LogLevel.debug;
      AppLog.sink = (level, tag, message, error, stackTrace) {
        captured.add('$message | $error');
      };

      AppLog.e(
        'auth',
        'refresh failed for user@vistar.test',
        error: Exception('Bearer sk_live_9f8a7b6c5d rejected'),
      );

      expect(captured, hasLength(1));
      expect(captured.single.contains('user@vistar.test'), isFalse,
          reason: 'the MESSAGE must be scrubbed');
      expect(captured.single.contains('sk_live_9f8a7b6c5d'), isFalse,
          reason:
              'the ERROR must be scrubbed too — it is the more likely leak');
    });
  });

  group('the level gate', () {
    test('records below the floor never reach the sink', () {
      var calls = 0;
      final originalSink = AppLog.sink;
      final originalLevel = AppLog.minimumLevel;
      addTearDown(() {
        AppLog.sink = originalSink;
        AppLog.minimumLevel = originalLevel;
      });

      AppLog.minimumLevel = LogLevel.warning;
      AppLog.sink = (_, __, ___, ____, _____) => calls++;

      AppLog.d('t', 'debug');
      AppLog.i('t', 'info');
      expect(calls, 0, reason: 'release drops the chatty levels entirely');

      AppLog.w('t', 'warning');
      AppLog.e('t', 'error');
      expect(calls, 2, reason: 'warnings and errors always get through');
    });

    test('levels are ordered so a sink can compare them', () {
      expect(LogLevel.error >= LogLevel.warning, isTrue);
      expect(LogLevel.debug >= LogLevel.warning, isFalse);
      expect(LogLevel.warning >= LogLevel.warning, isTrue);
    });
  });
}
