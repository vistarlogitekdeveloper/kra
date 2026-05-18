import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../network/connectivity_service.dart';

/// Slides down from the top of the screen when the device goes offline.
///
/// Designed to be placed inside a Stack at the top of any screen — see
/// [ConnectivityWrapper] which composes this for you.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);
    final isOnline = connectivity.maybeWhen(
      data: (online) => online,
      orElse: () => true, // be optimistic until we know
    );

    final mediaTopPadding = MediaQuery.paddingOf(context).top;

    return AnimatedSlide(
      offset: isOnline ? const Offset(0, -1) : Offset.zero,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: isOnline ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: Material(
          color: AppColors.error,
          elevation: 4,
          child: Container(
            padding: EdgeInsets.fromLTRB(16, mediaTopPadding + 8, 16, 10),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text(
                  AppStrings.offlineBanner,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
