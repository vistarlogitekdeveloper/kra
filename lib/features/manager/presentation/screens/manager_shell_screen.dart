import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/connectivity_wrapper.dart';

/// Outer scaffold for the manager module. Hosts the active subtree
/// from the inner StatefulShellRoute. The mode-switcher (My Team /
/// My Review) was removed because the My Review surface isn't built
/// — manager-capable roles self-rate via /employee/* directly. The
/// underlying mode provider + enum stay in place for when the round-
/// trip UX ships.
class ManagerShellScreen extends ConsumerWidget {
  final Widget child;
  const ManagerShellScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConnectivityWrapper(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(bottom: false, child: child),
      ),
    );
  }
}
