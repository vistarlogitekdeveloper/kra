import 'package:flutter/material.dart';

import 'offline_banner.dart';

/// Wraps a Scaffold-rooted screen with the animated [OfflineBanner].
///
/// Usage:
///   return ConnectivityWrapper(
///     child: Scaffold(...),
///   );
///
/// The banner overlays the Scaffold from the top — it does NOT push
/// content down, because reflowing the whole screen on every flicker
/// of connectivity is jarring. It sits above the AppBar/SafeArea.
class ConnectivityWrapper extends StatelessWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: OfflineBanner(),
        ),
      ],
    );
  }
}
