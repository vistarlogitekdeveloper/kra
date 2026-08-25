import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How far an arrow key moves the view. Roughly three text lines — the same
/// order as a mouse-wheel notch, so holding the key reads as a smooth scroll
/// rather than a jump.
const double kKeyboardScrollLine = 64;

/// Fraction of the viewport a Page Up / Page Down key moves. Less than a full
/// screen on purpose: keeping a sliver of the previous content visible is what
/// stops the reader losing their place.
const double kKeyboardScrollPageFactor = 0.85;

/// The scroll a key press should produce, in logical pixels, or null when the
/// key is not a scrolling key.
///
/// Positive scrolls DOWN (towards greater offset). Pulled out as a pure function
/// so the mapping is testable without a widget tree.
double? keyboardScrollDelta(LogicalKeyboardKey key, double viewportDimension) {
  if (key == LogicalKeyboardKey.arrowDown) return kKeyboardScrollLine;
  if (key == LogicalKeyboardKey.arrowUp) return -kKeyboardScrollLine;
  if (key == LogicalKeyboardKey.pageDown) {
    return viewportDimension * kKeyboardScrollPageFactor;
  }
  if (key == LogicalKeyboardKey.pageUp) {
    return -viewportDimension * kKeyboardScrollPageFactor;
  }
  return null;
}

/// True for the keys that jump to an end rather than move by an amount.
bool isKeyboardScrollJump(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end;

/// Makes the arrow, Page Up/Down and Home/End keys scroll the current screen on
/// laptops and the web.
///
/// Flutter's scrollables only respond to these keys when a widget INSIDE them
/// holds focus. On the web that rarely happens — clicking a non-focusable area
/// (most of a list) moves focus nowhere, so the keys do nothing and the app
/// feels broken on a laptop. This wraps the whole app once, so every screen
/// gains keyboard scrolling without touching the screens themselves.
///
/// How it reaches the screen's scrollable: it supplies the
/// [PrimaryScrollController], which every vertical scroll view attaches to
/// automatically when it is not given a controller of its own. Only three
/// scroll views in this app pass their own controller, so coverage is near
/// complete — see the limitation note on [_targetPosition].
///
/// Deliberately a no-op on touch platforms: there is no keyboard to serve, and
/// installing a shared controller there would be risk without benefit.
class KeyboardScrollScope extends StatefulWidget {
  final Widget child;
  const KeyboardScrollScope({super.key, required this.child});

  @override
  State<KeyboardScrollScope> createState() => _KeyboardScrollScopeState();
}

class _KeyboardScrollScopeState extends State<KeyboardScrollScope> {
  final ScrollController _controller = ScrollController();

  /// The scrollable that most recently reported activity. Used to disambiguate
  /// when several are attached at once — see [_targetPosition].
  ScrollPosition? _lastActive;

  static bool get _hasKeyboard =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Which scrollable to move.
  ///
  /// The app's shells keep several routes alive at once (an `IndexedStack` lays
  /// out every branch, not just the visible one), so more than one scroll view
  /// can be attached to the shared controller simultaneously. Picking blindly
  /// would sometimes scroll an off-screen list.
  ///
  /// So: prefer the one that last reported scroll activity — off-screen lists
  /// don't emit notifications from user interaction — and otherwise fall back to
  /// the one with the most content to scroll, which in practice is the screen's
  /// main list.
  ScrollPosition? _targetPosition() {
    final scrollable = _controller.positions
        .where((p) => p.hasContentDimensions && p.maxScrollExtent > 0)
        .toList();
    if (scrollable.isEmpty) return null;
    if (scrollable.length == 1) return scrollable.first;

    final last = _lastActive;
    if (last != null && scrollable.contains(last)) return last;

    scrollable.sort((a, b) => b.maxScrollExtent.compareTo(a.maxScrollExtent));
    return scrollable.first;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // KeyRepeat included so holding a key keeps scrolling.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Leave browser and OS shortcuts alone (Ctrl+Home, Alt+Left, ⌘+Down…).
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isAltPressed || keys.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final position = _targetPosition();
    if (position == null) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final double target;
    if (isKeyboardScrollJump(key)) {
      target = key == LogicalKeyboardKey.home
          ? position.minScrollExtent
          : position.maxScrollExtent;
    } else {
      final delta = keyboardScrollDelta(key, position.viewportDimension);
      if (delta == null) return KeyEventResult.ignored;
      target = position.pixels + delta;
    }

    final clamped =
        target.clamp(position.minScrollExtent, position.maxScrollExtent);
    // Already at that end — report ignored so the key can do something else
    // rather than being silently swallowed.
    if ((clamped - position.pixels).abs() < 0.5) return KeyEventResult.ignored;

    position.animateTo(
      clamped,
      // Short and linear-ish: a long curve fights key repeat, which would make
      // a held arrow key feel laggy.
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasKeyboard) return widget.child;

    return PrimaryScrollController(
      controller: _controller,
      // ESSENTIAL. A ScrollView only inherits the primary controller on
      // platforms listed here, and the default is MOBILE ONLY — so on desktop
      // and desktop-web (exactly where a keyboard exists) nothing would attach,
      // and every key press would find no scrollable and silently do nothing.
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final ctx = notification.context;
          if (ctx != null) {
            final scrollable = Scrollable.maybeOf(ctx);
            if (scrollable != null) _lastActive = scrollable.position;
          }
          return false; // observe only; never swallow the notification
        },
        // Placed ABOVE the app but below nothing else, so key events reach it
        // only after the focused widget has declined them. That ordering is what
        // keeps arrow keys working normally inside a text field: the field
        // handles them for caret movement and they never arrive here.
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: widget.child,
        ),
      ),
    );
  }
}
