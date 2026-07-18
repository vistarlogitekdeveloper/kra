import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_strings.dart';

/// An AppBar `leading` that puts BACK first and falls back to the drawer "☰".
///
/// Flutter's automatic leading checks `Scaffold.hasDrawer` **before** it checks
/// whether the route can pop:
///
/// ```dart
/// if (hasDrawer) {            // ← wins
///   leading = DrawerButton();
/// } else if (canPop) {
///   leading = BackButton();
/// }
/// ```
///
/// So every screen that owns a drawer renders the ☰ and **no back arrow — even
/// when you pushed onto it**, stranding the user with no way back (e.g. an
/// admin opening a colleague's KRA sheet from the review dashboard).
///
/// Use it as `leading: adaptiveLeading(context)`:
///   * something to pop → a back button;
///   * otherwise → `null`, which hands control back to the AppBar's normal
///     behaviour (the ☰ on a drawer screen, nothing on a plain tab root).
///
/// Returning null rather than a disabled arrow is deliberate: a tab root has
/// nowhere to go back to, and a button that does nothing is worse than no
/// button. The drawer stays reachable by edge-swipe on pushed screens.
Widget? adaptiveLeading(BuildContext context) {
  if (!context.canPop()) return null;
  return IconButton(
    icon: const Icon(Icons.arrow_back_rounded),
    tooltip: AppStrings.commonBack,
    onPressed: () => context.pop(),
  );
}
