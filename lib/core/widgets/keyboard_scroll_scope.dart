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

/// True for any key this scope acts on.
///
/// Separate from [keyboardScrollDelta] so a key can be rejected WITHOUT a
/// viewport to measure against — the handler screens out every other key press
/// in the app before paying for a scrollable lookup.
bool isKeyboardScrollKey(LogicalKeyboardKey key) =>
    isKeyboardScrollJump(key) ||
    key == LogicalKeyboardKey.arrowDown ||
    key == LogicalKeyboardKey.arrowUp ||
    key == LogicalKeyboardKey.pageDown ||
    key == LogicalKeyboardKey.pageUp;

/// Makes the arrow, Page Up/Down and Home/End keys scroll the current screen on
/// laptops and the web.
///
/// Flutter's scrollables only respond to these keys when a widget INSIDE them
/// holds focus. On the web that rarely happens — clicking a non-focusable area
/// (most of a list) moves focus nowhere — so the keys do nothing and the app
/// feels broken on a laptop. This wraps the whole app once, so every screen
/// gains keyboard scrolling without touching the screens themselves.
///
/// How it finds the screen's scrollable: it WALKS ITS SUBTREE for live
/// [ScrollableState]s. The obvious alternative — supplying a
/// [PrimaryScrollController] and reading its attached positions — silently
/// covered only about half the app: `PagedListView` (every paginated list here),
/// the employees list and the audit log each construct their OWN
/// ScrollController, and a scroll view given a controller never attaches to the
/// primary one. Those screens are exactly where a keyboard user has the most to
/// scroll, and there the keys did nothing at all.
///
/// Deliberately inert on touch platforms: there is no keyboard to serve.
class KeyboardScrollScope extends StatefulWidget {
  final Widget child;
  const KeyboardScrollScope({super.key, required this.child});

  @override
  State<KeyboardScrollScope> createState() => _KeyboardScrollScopeState();
}

class _KeyboardScrollScopeState extends State<KeyboardScrollScope> {
  /// Marks the subtree that gets searched for scrollables.
  final GlobalKey _subtree = GlobalKey();

  final FocusNode _node = FocusNode(debugLabel: 'KeyboardScrollScope');

  /// The scrollable that most recently reported activity OR laid itself out.
  /// Used to disambiguate when several are alive at once — see [_target].
  ScrollPosition? _lastActive;

  static bool get _hasKeyboard =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    // Second delivery path, for when focus sits OUTSIDE this subtree — after a
    // click on a non-focusable area the primary focus can be the root scope,
    // which is an ANCESTOR of our Focus, so key events never reach it. A
    // hardware-level handler sees every event regardless of the focus path.
    if (_hasKeyboard) {
      HardwareKeyboard.instance.addHandler(_onHardwareKey);
    }
  }

  @override
  void dispose() {
    if (_hasKeyboard) {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    }
    _node.dispose();
    super.dispose();
  }

  /// Every live, vertical, actually-scrollable position in the subtree.
  ///
  /// Walking the element tree per key press costs a fraction of a millisecond
  /// and — unlike caching positions — can never hand back one belonging to a
  /// disposed scrollable, which is the failure mode that makes cached-position
  /// approaches crash on navigation.
  List<ScrollPosition> _livePositions() {
    final found = <ScrollPosition>[];
    void visit(Element el) {
      if (el is StatefulElement && el.state is ScrollableState) {
        final state = el.state as ScrollableState;
        try {
          final position = state.position;
          if (position.axis == Axis.vertical &&
              position.hasContentDimensions &&
              position.hasPixels &&
              position.maxScrollExtent > 0) {
            found.add(position);
          }
        } catch (_) {
          // Not attached to a viewport yet — nothing to scroll.
        }
      }
      el.visitChildren(visit);
    }

    final context = _subtree.currentContext;
    if (context is Element) context.visitChildren(visit);
    return found;
  }

  /// Which scrollable to move.
  ///
  /// The app's shells keep several routes alive at once (an `IndexedStack` lays
  /// out every branch, not just the visible one), so more than one scroll view
  /// can be live simultaneously. Picking blindly would sometimes scroll an
  /// off-screen list.
  ///
  /// So: prefer the one that last reported activity or laid itself out — a
  /// freshly navigated-to screen announces its metrics, and an off-screen branch
  /// that nobody touched does not — and otherwise fall back to the one with the
  /// most content to scroll, which in practice is the screen's main list.
  ScrollPosition? _target() {
    final candidates = _livePositions();
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;

    final last = _lastActive;
    if (last != null && candidates.contains(last)) return last;

    candidates.sort((a, b) => b.maxScrollExtent.compareTo(a.maxScrollExtent));
    return candidates.first;
  }

  /// True when the caret owns the arrow keys.
  ///
  /// Checked on BOTH delivery paths. The focus path is safe by construction (a
  /// focused field consumes the key before it bubbles up here), but the
  /// hardware path runs before focus dispatch, so without this typing in any
  /// form would scroll the page under the user.
  static bool get _editingText {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    // EditableText builds its own Focus, so from that node's context the
    // EditableText is an ancestor.
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _remember(BuildContext? context) {
    if (context == null) return;
    final scrollable = Scrollable.maybeOf(context);
    final position = scrollable?.position;
    if (position != null && position.axis == Axis.vertical) {
      _lastActive = position;
    }
  }

  bool _onHardwareKey(KeyEvent event) {
    // When our Focus IS in the focus path it has already had its chance at this
    // event; handling it again here would scroll twice per press.
    if (_node.hasFocus) return false;
    return _handle(event);
  }

  KeyEventResult _onFocusKey(FocusNode node, KeyEvent event) =>
      _handle(event) ? KeyEventResult.handled : KeyEventResult.ignored;

  bool _handle(KeyEvent event) {
    // KeyRepeat included so holding a key keeps scrolling.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // Leave browser and OS shortcuts alone (Ctrl+Home, Alt+Left, ⌘+Down…).
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    if (_editingText) return false;

    final key = event.logicalKey;
    // Screen out non-scroll keys BEFORE hunting for a scrollable: every other
    // key press in the app would otherwise pay for an element-tree walk.
    if (!isKeyboardScrollKey(key)) return false;

    final position = _target();
    if (position == null) return false;

    final double destination;
    if (isKeyboardScrollJump(key)) {
      destination = key == LogicalKeyboardKey.home
          ? position.minScrollExtent
          : position.maxScrollExtent;
    } else {
      final delta = keyboardScrollDelta(key, position.viewportDimension);
      if (delta == null) return false;
      destination = position.pixels + delta;
    }

    final clamped =
        destination.clamp(position.minScrollExtent, position.maxScrollExtent);
    // Already at that end — report unhandled so the key can do something else
    // rather than being silently swallowed.
    if ((clamped - position.pixels).abs() < 0.5) return false;

    position.animateTo(
      clamped,
      // Short and linear-ish: a long curve fights key repeat, which would make
      // a held arrow key feel laggy.
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasKeyboard) return widget.child;

    // Two notification types, because they answer different questions:
    // ScrollNotification means "the user moved this one"; ScrollMetricsNotification
    // means "this one just laid itself out", which is what identifies the list on
    // a screen the user has navigated to but not yet touched.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _remember(notification.context);
        return false; // observe only; never swallow
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _remember(notification.context);
          return false;
        },
        // Placed ABOVE the app, so key events reach it only after the focused
        // widget has declined them. That ordering is what keeps arrow keys
        // working normally inside a text field.
        child: Focus(
          focusNode: _node,
          autofocus: true,
          onKeyEvent: _onFocusKey,
          child: KeyedSubtree(key: _subtree, child: widget.child),
        ),
      ),
    );
  }
}
