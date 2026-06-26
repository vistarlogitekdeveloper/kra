import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';

/// A delayed "the server is waking up" hint shown over a loading state.
///
/// Stays invisible for [delay] (default 7s) so quick loads never show it,
/// then fades in. The backend is on Render's free tier and can take
/// 30–60s to wake from idle — without this cue, that wait reads as a hang.
///
/// Drop it at the top of a loading list/skeleton; it manages its own
/// timer and renders nothing until the delay elapses.
class SlowLoadHint extends StatefulWidget {
  final Duration delay;
  final String message;

  const SlowLoadHint({
    super.key,
    this.delay = const Duration(seconds: 7),
    this.message = AppStrings.slowLoadHint,
  });

  @override
  State<SlowLoadHint> createState() => _SlowLoadHintState();
}

class _SlowLoadHintState extends State<SlowLoadHint> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: AnimatedOpacity(
        opacity: _show ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primaryPurple.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppColors.primaryPurple),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
