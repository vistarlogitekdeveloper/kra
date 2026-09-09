import 'package:flutter/foundation.dart';

/// Severity of a log record. Ordered, so a sink can filter by minimum level.
enum LogLevel {
  debug(0, 'DEBUG'),
  info(1, 'INFO'),
  warning(2, 'WARN'),
  error(3, 'ERROR');

  const LogLevel(this.rank, this.label);

  final int rank;
  final String label;

  bool operator >=(LogLevel other) => rank >= other.rank;
}

/// Where a record goes once [AppLog] has decided it should be emitted.
///
/// Exists so crash reporting (Crashlytics / Sentry) can be attached in
/// `bootstrap` without editing a single call site — the standard requires a
/// scrubbing hook, and a hook is only useful if there is exactly one place to
/// install it.
typedef LogSink = void Function(
  LogLevel level,
  String tag,
  String message,
  Object? error,
  StackTrace? stackTrace,
);

/// Structured, level-gated, scrubbed application log.
///
/// Replaces bare `debugPrint` at call sites. `debugPrint` is NOT stripped from
/// release builds — it writes to the platform log there exactly as it does in
/// debug — so a `debugPrint('parse failed: $e')` ships whatever the exception's
/// `toString()` happens to contain, which for a Dio error is the request path,
/// the status line and often a body fragment. That is the whole reason this
/// exists.
///
/// Two independent protections, because either alone is insufficient:
///
///  * **Level gating.** In release the floor is [LogLevel.warning], so the
///    chatty `debug`/`info` records never reach a sink at all.
///  * **Scrubbing.** Every message and error is passed through [scrub] on the
///    way out, regardless of level or build mode. A scrubber that only runs in
///    release is a scrubber nobody has ever seen work.
abstract final class AppLog {
  /// Records below this are dropped without being formatted.
  ///
  /// Debug builds want everything. Release keeps warnings and errors, because
  /// silence in production is its own failure — the standard asks for
  /// crash-free-rate and API error-rate instrumentation, and neither is
  /// possible if nothing is recorded.
  static LogLevel minimumLevel =
      kReleaseMode ? LogLevel.warning : LogLevel.debug;

  /// Installed by `bootstrap`. Defaults to the console.
  static LogSink sink = _consoleSink;

  static void d(String tag, String message) =>
      _emit(LogLevel.debug, tag, message, null, null);

  static void i(String tag, String message) =>
      _emit(LogLevel.info, tag, message, null, null);

  static void w(String tag, String message, {Object? error}) =>
      _emit(LogLevel.warning, tag, message, error, null);

  static void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _emit(LogLevel.error, tag, message, error, stackTrace);

  static void _emit(
    LogLevel level,
    String tag,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (!(level >= minimumLevel)) return;
    sink(level, tag, scrub(message), error == null ? null : scrub('$error'),
        stackTrace);
  }

  /// Redacts the things that must never reach a log line.
  ///
  /// Deliberately pattern-based rather than a list of known field names: the
  /// input here is an arbitrary `toString()` of an exception, so there is no
  /// schema to key off. Over-redaction is the acceptable failure — a log that
  /// says `[jwt]` is still useful, a log that leaks a session is not.
  ///
  /// Visible for testing so the patterns are pinned by tests rather than by
  /// hope; see test/core/observability/app_logger_test.dart.
  @visibleForTesting
  static String scrub(String input) {
    var out = input;
    for (final rule in _scrubbers) {
      // `replaceAllMapped`, not `replaceAll`: Dart's String replacement does
      // NOT expand `$1` backreferences, so a rule written that way silently
      // emitted the literal text `$1` and threw away the captured key name —
      // leaving a log that said `[redacted]` without saying what was.
      out = out.replaceAllMapped(rule.pattern, rule.replacement);
    }
    return out;
  }

  static final List<_Scrubber> _scrubbers = [
    // JWTs — three base64url segments. Matched before the generic token rule
    // so the whole token goes, not just its middle.
    _Scrubber(
      RegExp(r'\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b'),
      (_) => '[jwt]',
    ),
    // `Bearer <anything>` and the JSON shapes tokens travel in.
    _Scrubber(
      RegExp(r'Bearer\s+\S+', caseSensitive: false),
      (_) => 'Bearer [token]',
    ),
    _Scrubber(
      RegExp(
        r'"?(access_?token|refresh_?token|password|newPassword|oldPassword|token|secret|apiKey)"?\s*[:=]\s*"?[^",;}\s]+',
        caseSensitive: false,
      ),
      // Keeps the captured key NAME and drops only its value, so the line
      // still reads `password: [redacted]`. A log that says only `[redacted]`
      // is undiagnosable, and an undiagnosable log is how a scrubber ends up
      // switched off by the next person debugging at 2am.
      (m) => '${m[1]}: [redacted]',
    ),
    // Email addresses — PII, and the app logs identifiers on auth failures.
    _Scrubber(
      RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b'),
      (_) => '[email]',
    ),
    // Query strings. The standard forbids full URLs with query params, and a
    // Dio error stringifies the whole URI.
    _Scrubber(RegExp(r'\?[^\s]*'), (_) => '?[query]'),
    // Long digit runs: phone numbers, account and employee identifiers.
    _Scrubber(RegExp(r'\b\d{7,}\b'), (_) => '[number]'),
  ];

  static void _consoleSink(
    LogLevel level,
    String tag,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final buffer = StringBuffer('[${level.label}] $tag: $message');
    if (error != null) buffer.write(' | $error');
    debugPrint(buffer.toString());
    // Stack traces only in debug: they are large, and in release the sink is
    // expected to be a crash reporter that captures them structurally.
    if (stackTrace != null && kDebugMode) debugPrint('$stackTrace');
  }
}

class _Scrubber {
  const _Scrubber(this.pattern, this.replacement);

  final Pattern pattern;

  /// A function of the match rather than a plain String, so a rule can keep
  /// part of what it matched — see the token/password rule in
  /// [AppLog.scrub]'s list.
  final String Function(Match) replacement;
}
