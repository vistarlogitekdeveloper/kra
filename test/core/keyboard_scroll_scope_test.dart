import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/widgets/keyboard_scroll_scope.dart';

/// Keyboard scrolling exists because Flutter's scrollables ignore arrow keys
/// unless a widget INSIDE them holds focus — which on the web is usually
/// nothing, so a laptop user cannot scroll with the keyboard at all.
void main() {
  group('keyboardScrollDelta', () {
    test('arrows move by a line, down positive and up negative', () {
      expect(keyboardScrollDelta(LogicalKeyboardKey.arrowDown, 800),
          kKeyboardScrollLine);
      expect(keyboardScrollDelta(LogicalKeyboardKey.arrowUp, 800),
          -kKeyboardScrollLine);
    });

    test('page keys move by most of the viewport, not all of it — leaving some '
        'previous content visible is what stops the reader losing their place',
        () {
      final down = keyboardScrollDelta(LogicalKeyboardKey.pageDown, 800)!;
      expect(down, lessThan(800));
      expect(down, greaterThan(400));
      expect(keyboardScrollDelta(LogicalKeyboardKey.pageUp, 800), -down);
    });

    test('page distance scales with the viewport', () {
      final small = keyboardScrollDelta(LogicalKeyboardKey.pageDown, 400)!;
      final large = keyboardScrollDelta(LogicalKeyboardKey.pageDown, 1200)!;
      expect(large, greaterThan(small));
    });

    test('non-scrolling keys return null so they are left alone', () {
      for (final k in [
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ]) {
        expect(keyboardScrollDelta(k, 800), isNull, reason: '$k');
      }
    });

    test('home and end are jumps, not deltas', () {
      expect(isKeyboardScrollJump(LogicalKeyboardKey.home), isTrue);
      expect(isKeyboardScrollJump(LogicalKeyboardKey.end), isTrue);
      expect(isKeyboardScrollJump(LogicalKeyboardKey.arrowDown), isFalse);
    });
  });

  group('KeyboardScrollScope in a widget tree', () {
    // A long list with NO controller of its own — the ordinary case in this app,
    // and the one that attaches to the scope's PrimaryScrollController.
    Widget app() => MaterialApp(
          home: KeyboardScrollScope(
            child: Scaffold(
              body: ListView(
                children: [
                  for (var i = 0; i < 60; i++)
                    SizedBox(height: 60, child: Text('row $i')),
                ],
              ),
            ),
          ),
        );

    ScrollPosition positionOf(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    testWidgets('arrow down scrolls, arrow up comes back', (tester) async {
      await onDesktop(() async {
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();

        final position = positionOf(tester);
        expect(position.pixels, 0);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(position.pixels, greaterThan(0));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(position.pixels, 0);
      });
    });

    testWidgets('page down moves further than a single arrow press',
        (tester) async {
      await onDesktop(() async {
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        final position = positionOf(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final afterArrow = position.pixels;

        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
        expect(position.pixels - afterArrow, greaterThan(afterArrow));
      });
    });

    testWidgets('end jumps to the bottom and home back to the top',
        (tester) async {
      await onDesktop(() async {
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        final position = positionOf(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        expect(position.pixels, position.maxScrollExtent);

        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pumpAndSettle();
        expect(position.pixels, position.minScrollExtent);
      });
    });

    testWidgets('a focused text field keeps the arrow keys for its caret',
        (tester) async {
      await onDesktop(() async {
        await tester.pumpWidget(MaterialApp(
          home: KeyboardScrollScope(
            child: Scaffold(
              body: Column(
                children: [
                  TextField(
                    controller: TextEditingController(text: 'hello'),
                    autofocus: true,
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (var i = 0; i < 60; i++) const SizedBox(height: 60),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        // The field holds focus, so it consumes the arrows first and the list
        // must stay put — otherwise typing in a form would scroll the page.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(positionOf(tester).pixels, 0);
      });
    });

    testWidgets('a list with nothing to scroll is left alone', (tester) async {
      await onDesktop(() async {
        await tester.pumpWidget(MaterialApp(
          home: KeyboardScrollScope(
            child: Scaffold(
              body: ListView(children: const [SizedBox(height: 40)]),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(positionOf(tester).pixels, 0);
      });
    });

    testWidgets('inert on touch platforms — there is no keyboard to serve, so '
        'the shared controller is never installed there', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(positionOf(tester).pixels, 0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

/// Runs [body] with a desktop target platform.
///
/// The scope is intentionally inert on touch platforms and flutter_test reports
/// Android by default, so without this every widget test here would pass
/// vacuously against a pass-through widget. The reset must happen INSIDE the
/// test body — hence the finally rather than a tearDown, which runs after the
/// framework's "debug variable was changed by the test" check.
Future<void> onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
