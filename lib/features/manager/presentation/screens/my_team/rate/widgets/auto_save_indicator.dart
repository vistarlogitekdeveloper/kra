import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../providers/manager_rate_providers.dart';

/// Tiny status pill that sits in the app-bar. Four states:
///   - saving       (auto-save POST in flight)
///   - saved <when> (most recent save succeeded — "Saved 3s ago")
///   - error        (last attempt failed, with a Retry chip)
///   - idle         (no changes since last save / nothing to save)
class AutoSaveIndicator extends ConsumerStatefulWidget {
  const AutoSaveIndicator({super.key});

  @override
  ConsumerState<AutoSaveIndicator> createState() =>
      _AutoSaveIndicatorState();
}

class _AutoSaveIndicatorState extends ConsumerState<AutoSaveIndicator> {
  /// Refresh ticker — the "Saved 3s ago" label needs to update even
  /// when no provider state changed, so we poke setState every 15s.
  late final Stream<DateTime> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(
        const Duration(seconds: 15), (_) => DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: _ticker,
      builder: (_, __) => _buildIndicator(),
    );
  }

  Widget _buildIndicator() {
    final state = ref.watch(managerRateProvider);
    if (state.isAutoSaving) {
      return const _Pill(
        icon: Icons.cloud_sync_rounded,
        label: 'Saving…',
        fg: AppColors.primaryPurple,
      );
    }
    if (state.autoSaveError != null) {
      return _ErrorPill(
        onRetry: () =>
            ref.read(managerRateProvider.notifier).retryAutoSave(),
      );
    }
    final savedAt = state.lastSavedAt;
    if (savedAt != null) {
      final ago = EmployeeFormatters.relativeTime(savedAt);
      return _Pill(
        icon: Icons.cloud_done_rounded,
        label: 'Saved $ago',
        fg: AppColors.success,
      );
    }
    return const SizedBox.shrink();
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color fg;

  const _Pill({
    required this.icon,
    required this.label,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: fg,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPill extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorPill({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Material(
        color: AppColors.accentRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onRetry,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded,
                    size: 12, color: AppColors.accentRed),
                SizedBox(width: 4),
                Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentRed,
                    letterSpacing: 0.3,
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
