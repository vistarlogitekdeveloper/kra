import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/connectivity_wrapper.dart';
import '../widgets/mode_segmented_switcher.dart';

/// Outer scaffold for the manager module. Hosts:
///   - The mode segmented switcher (My Team / My Review)
///   - The active mode's subtree (provided via the navigationShell
///     param from `StatefulShellRoute.indexedStack` in app_router)
///
/// The inner `StatefulShellRoute` keeps each mode's nav stack alive
/// (so deep-dives survive mode switches), and the switcher widget
/// drives navigation through the `managerModeProvider`.
class ManagerShellScreen extends ConsumerWidget {
  final Widget child;
  const ManagerShellScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConnectivityWrapper(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const ModeSegmentedSwitcher(),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
