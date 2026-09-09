import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The four error channels must all stay wired.
///
/// Flutter raises errors through four independent paths, and an unwired one is
/// invisible until a real user hits it:
///
///   FlutterError.onError                    build / layout / paint
///   PlatformDispatcher.instance.onError     uncaught async
///   runZonedGuarded                         everything else on the zone
///   ErrorWidget.builder                     the last line of defence
///
/// The last is the one that shows. Without it a build error paints the
/// grey-on-red "Exception caught by rendering library" box — in release, to a
/// customer. None of the four were wired before; all four are asserted here
/// because deleting one is a silent, one-line regression that no behavioural
/// test in this suite would notice.
///
/// Source-level rather than behavioural on purpose. Installing real handlers
/// inside `flutter_test` fights the test binding's own error capture, and a
/// test that swaps them out and back proves the test harness works, not that
/// `main()` wires anything. What matters is that the production entrypoint
/// still calls them, so that is what this reads.
void main() {
  final bootstrap = File('lib/app/bootstrap.dart').readAsStringSync();
  final mainDart = File('lib/main.dart').readAsStringSync();

  /// Source with `//` comments removed, for assertions about CODE.
  ///
  /// Needed because the first version of the `.when()` check below failed
  /// against a comment that merely mentioned `.when()` while explaining why
  /// the code does not use it. A source-level test that reads prose reports
  /// the opposite of the truth, which is worse than no test.
  ///
  /// Line comments only — good enough here, and it deliberately does not try
  /// to parse Dart. If a future assertion needs to distinguish a `//` inside a
  /// string literal, that assertion wants the analyzer, not a regex.
  String codeOnly(String src) => src.split('\n').map((l) {
        final i = l.indexOf('//');
        return i == -1 ? l : l.substring(0, i);
      }).join('\n');

  final mainCode = codeOnly(mainDart);
  final bootstrapCode = codeOnly(bootstrap);

  group('bootstrap wires every error channel', () {
    const required = {
      'FlutterError.onError': 'framework build/layout/paint errors',
      'PlatformDispatcher.instance.onError': 'uncaught async errors',
      'runZonedGuarded': 'errors escaping the zone',
      'ErrorWidget.builder':
          'the red-screen fallback a user would otherwise see',
    };

    for (final entry in required.entries) {
      test('installs ${entry.key}', () {
        expect(
          bootstrapCode.contains(entry.key),
          isTrue,
          reason: 'bootstrap.dart no longer installs ${entry.key}, so '
              '${entry.value} are unhandled again',
        );
      });
    }

    test('runApp happens INSIDE the guarded zone', () {
      // Calling runApp beside runZonedGuarded rather than within it leaves the
      // app running on the root zone, where the handler catches nothing.
      final guardIndex = bootstrapCode.indexOf('runZonedGuarded');
      final runAppIndex = bootstrapCode.indexOf('runApp(');
      expect(guardIndex, greaterThan(-1));
      expect(runAppIndex, greaterThan(guardIndex),
          reason: 'runApp must be called inside the runZonedGuarded callback');
    });

    test('the fallback widget does not read from an InheritedWidget', () {
      // It renders *because* the tree above it failed, so `Theme.of`,
      // `MediaQuery.of` or a localisation lookup could each be the very thing
      // that threw — and a fallback that throws gives an infinite error loop.
      //
      // Checked against the stripped source: bootstrap.dart's own doc comment
      // names these very identifiers while explaining that it avoids them.
      for (final forbidden in [
        'Theme.of(',
        'MediaQuery.of(',
        'MediaQuery.sizeOf(',
        'AppStrings.',
      ]) {
        expect(
          bootstrapCode.contains(forbidden),
          isFalse,
          reason: 'the crash fallback must not depend on $forbidden — it runs '
              'when the tree above it has already failed',
        );
      }
    });

    test('the exception text is shown in debug ONLY', () {
      // An exception string is useless to a user and is a disclosure risk.
      expect(bootstrapCode.contains('kDebugMode'), isTrue,
          reason: 'the raw exception must be gated behind kDebugMode');
    });
  });

  group('main() goes through bootstrap', () {
    test('main delegates to bootstrap rather than calling runApp itself', () {
      expect(mainCode.contains('bootstrap('), isTrue,
          reason: 'main() bypassing bootstrap unwires all four handlers');
      final collapsed = mainCode.replaceAll(RegExp(r'\s+'), '');
      expect(
        collapsed.contains('voidmain()=>bootstrap('),
        isTrue,
        reason: 'main must hand off to bootstrap as its whole body',
      );
    });

    test('main does not call runApp directly', () {
      expect(mainCode.contains('runApp('), isFalse,
          reason: 'a direct runApp in main() escapes the guarded zone');
    });

    test('the app is consumed with exhaustive pattern matching, not .when()',
        () {
      // §4: AsyncValue is sealed, so a switch proves every state is handled
      // and a future state cannot fall into a default branch unnoticed.
      expect(mainCode.contains('.when('), isFalse,
          reason: 'use a switch over AsyncLoading/AsyncData/AsyncError');
      expect(mainCode.contains('AsyncLoading()'), isTrue);
    });

    test('no `Widget _buildX()` builder methods', () {
      // §14: a builder method defeats const-rebuild pruning; the subtree has
      // to be a widget class to be prunable.
      expect(
        RegExp(r'Widget\s+_[a-zA-Z]\w*\(').hasMatch(mainCode),
        isFalse,
        reason: 'extract a private widget class instead',
      );
    });
  });
}
