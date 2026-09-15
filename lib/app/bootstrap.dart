import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/observability/app_logger.dart';

const _tag = 'bootstrap';

/// Starts the app with every error path terminated somewhere deliberate.
///
/// Four handlers, because Flutter raises errors through four different
/// channels and any one left unwired shows the user something we did not
/// design:
///
///  * [FlutterError.onError] — framework errors raised during build, layout
///    and paint.
///  * [PlatformDispatcher.instance.onError] — uncaught async errors that
///    escape the framework entirely (a `Future` nobody awaited).
///  * [runZonedGuarded] — everything else on this zone, including errors
///    thrown out of a synchronous callback the framework does not wrap.
///  * [ErrorWidget.builder] — the LAST line of defence. Without it, a build
///    error paints the grey-on-red "Exception caught by rendering library"
///    box, in release, to a real user. That is the specific outcome this
///    function exists to make impossible.
///
/// Wiring order matters: the handlers are installed BEFORE
/// `WidgetsFlutterBinding.ensureInitialized()` completes any work that could
/// itself throw, and `runApp` is called inside the guarded zone rather than
/// beside it.
Future<void> bootstrap(Widget Function() builder) async {
  ErrorWidget.builder = (details) => _CrashFallback(details: details);

  FlutterError.onError = (details) {
    // Keep the console presentation in debug — it is genuinely the best
    // debugging surface Flutter has — and record through the app's sink in
    // both modes so a crash reporter attached to [AppLog.sink] sees it.
    if (kDebugMode) FlutterError.presentError(details);
    AppLog.e(
      _tag,
      'flutter error in ${details.library ?? 'framework'}',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.e(_tag, 'uncaught async error', error: error, stackTrace: stack);
    // Returning true marks the error handled, which stops the platform
    // terminating the isolate for something we have already recorded.
    return true;
  };

  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(builder());
  }, (error, stack) {
    AppLog.e(_tag, 'uncaught zone error', error: error, stackTrace: stack);
  });
}

/// What a user sees instead of the red error box.
///
/// Intentionally plain and self-contained: it must render when the widget tree
/// above it has already failed, so it takes nothing from an InheritedWidget —
/// no `Theme.of`, no `MediaQuery.of`, no localisation lookup. Any of those
/// could be the very thing that just threw.
///
/// It shows the exception in debug only. In release the user gets a sentence
/// they can act on, because an exception string is both useless to them and a
/// disclosure risk.
class _CrashFallback extends StatelessWidget {
  const _CrashFallback({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 14),
                Text(
                  'Something went wrong on this screen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Go back and try again. If it keeps happening, please '
                  'report it to your HR admin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${details.exception}',
                    textAlign: TextAlign.center,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      // Const because AppColors.error is one of the few fixed
                      // tokens — most of the palette is a brightness-dependent
                      // getter and cannot appear in a const expression.
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
