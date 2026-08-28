import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vistar_app/core/widgets/keyboard_scroll_scope.dart';
import 'package:vistar_app/core/widgets/paged_list_view.dart';

/// Keyboard scrolling, exercised through the app's REAL structure rather than a
/// bare ListView: `MaterialApp.router` + GoRouter, the scope installed in the
/// router's `builder`, the brightness-keyed subtree main.dart uses, and an
/// actual [PagedListView] — which supplies its own ScrollController and is the
/// list widget nearly every screen here scrolls.
///
/// The simplified tests passed while the shipped web app did nothing, so the
/// gap was in the fixture, not the feature. These pin the real shape.
void main() {
  /// A screen whose list is a real PagedListView, plus a focusable button — so
  /// a test can put focus where a user's click would leave it.
  Widget listScreen({FocusNode? buttonFocus}) => Scaffold(
        body: Column(
          children: [
            TextButton(
              focusNode: buttonFocus,
              onPressed: () {},
              child: const Text('a button'),
            ),
            Expanded(
              child: PagedListView<int>(
                items: List<int>.generate(80, (i) => i),
                itemBuilder: (_, __, item) =>
                    SizedBox(height: 60, child: Text('row $item')),
                isInitialLoading: false,
                isLoadingMore: false,
                hasMore: false,
                onLoadMore: () {},
                onRefresh: () async {},
              ),
            ),
          ],
        ),
      );

  Widget app({FocusNode? buttonFocus}) {
    final router = GoRouter(
      routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => listScreen(buttonFocus: buttonFocus)),
      ],
    );
    return MaterialApp.router(
      routerConfig: router,
      // Exactly what main.dart does, including the KeyedSubtree the theme
      // toggle needs — the scope sits OUTSIDE it so it survives a theme flip.
      builder: (context, child) => KeyboardScrollScope(
        child: KeyedSubtree(
          key: const ValueKey(Brightness.light),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  /// The PagedListView's own scrollable, not the RefreshIndicator's.
  ScrollPosition listPosition(WidgetTester tester) {
    final states = tester.stateList<ScrollableState>(find.byType(Scrollable));
    for (final s in states) {
      if (s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0) {
        return s.position;
      }
    }
    fail('no scrollable vertical list found');
  }

  testWidgets('arrow keys scroll a PagedListView through the real router shape',
      (tester) async {
    await onDesktop(() async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final position = listPosition(tester);
      expect(position.pixels, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0),
          reason: 'PagedListView owns its controller — the case that was dead');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
    });
  });

  testWidgets(
      'still scrolls when focus sits on a button, as it does after a '
      'user clicks something', (tester) async {
    await onDesktop(() async {
      final buttonFocus = FocusNode();
      addTearDown(buttonFocus.dispose);
      await tester.pumpWidget(app(buttonFocus: buttonFocus));
      await tester.pumpAndSettle();

      buttonFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(buttonFocus.hasPrimaryFocus, isTrue);

      final position = listPosition(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0),
          reason: 'the key must reach the scope by bubbling past the button');
    });
  });

  testWidgets('Page Down and End work through the same shape', (tester) async {
    await onDesktop(() async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final position = listPosition(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      final afterPage = position.pixels;
      expect(afterPage, greaterThan(kKeyboardScrollLine));

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(position.pixels, position.maxScrollExtent);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(position.pixels, position.minScrollExtent);
    });
  });
}

/// Runs [body] with a desktop target platform — the scope is inert on touch
/// platforms and flutter_test reports Android by default, so without this every
/// assertion here would pass against a pass-through widget. Reset inside the
/// body, because a tearDown runs after the framework's "debug variable was
/// changed by the test" check.
Future<void> onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
