import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/enums/review_flow.dart';
import '../../../../reviews/data/models/rating_access.dart';
import 'rating_access_copy.dart';

/// One rating stage of the month: who rates it, whether it is open and why,
/// the override behind that, and the three things a super admin can do.
class RatingAccessStageCard extends StatelessWidget {
  final RatingAccessStage entry;
  final ReviewFlow flow;
  final DateTime now;
  final bool busy;
  final VoidCallback onOpenUntil;
  final VoidCallback onClose;
  final VoidCallback onUseDeadline;

  const RatingAccessStageCard({
    super.key,
    required this.entry,
    required this.flow,
    required this.now,
    required this.busy,
    required this.onOpenUntil,
    required this.onClose,
    required this.onUseDeadline,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _Tone.of(ratingAccessPhase(entry.window, now));
    final adminOverride = entry.adminOverride;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ratingAccessStageLabel(entry.stage, flow),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            ratingAccessSeatDescription(entry.stage, flow),
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          _StatusLine(
            text: ratingAccessStatusLine(entry.window, now),
            tone: tone,
          ),
          if (adminOverride != null)
            _OverrideDetails(
              adminOverride: adminOverride,
              inert: entry.overrideIsInert,
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onOpenUntil,
                icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                label: const Text(AppStrings.ratingAccessActionOpenUntil),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  iconColor: AppColors.primaryPurple,
                  minimumSize: _actionSize,
                  padding: _actionPadding,
                ),
              ),
              // Already closed by an override: closing again changes nothing.
              if (adminOverride?.mode != RatingAccessMode.closed)
                TextButton.icon(
                  onPressed: busy ? null : onClose,
                  icon: const Icon(Icons.lock_rounded, size: 18),
                  label: const Text(AppStrings.ratingAccessActionClose),
                  style: _textAction(AppColors.error),
                ),
              if (adminOverride != null)
                TextButton.icon(
                  onPressed: busy ? null : onUseDeadline,
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text(AppStrings.ratingAccessActionUseDeadline),
                  style: _textAction(AppColors.primaryPurple),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Every action is at least a 48 px target, on desktop themes too.
const Size _actionSize = Size(48, 48);
const EdgeInsets _actionPadding =
    EdgeInsets.symmetric(horizontal: 14, vertical: 12);

/// A text action whose label keeps full contrast; [iconColor] carries its
/// meaning.
ButtonStyle _textAction(Color iconColor) => TextButton.styleFrom(
      foregroundColor: AppColors.textPrimary,
      iconColor: iconColor,
      minimumSize: _actionSize,
      padding: _actionPadding,
    );

/// How a phase looks: an icon and a tint. The words always say the same thing,
/// so nothing is conveyed by colour alone.
class _Tone {
  final Color color;
  final IconData icon;
  const _Tone(this.color, this.icon);

  static _Tone of(RatingAccessPhase phase) {
    switch (phase) {
      case RatingAccessPhase.notYetOpen:
        return const _Tone(AppColors.info, Icons.schedule_rounded);
      case RatingAccessPhase.deadlineOpen:
        return const _Tone(AppColors.success, Icons.lock_open_rounded);
      case RatingAccessPhase.reopened:
        return const _Tone(AppColors.accentOrange, Icons.more_time_rounded);
      case RatingAccessPhase.deadlineClosed:
      case RatingAccessPhase.reopenEnded:
        return _Tone(AppColors.textMuted, Icons.lock_rounded);
      case RatingAccessPhase.closedByAdmin:
        return const _Tone(AppColors.error, Icons.block_rounded);
    }
  }
}

class _StatusLine extends StatelessWidget {
  final String text;
  final _Tone tone;
  const _StatusLine({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tone.color.withValues(alpha: 0.14),
          ),
          child: Icon(tone.icon, size: 16, color: tone.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _OverrideDetails extends StatelessWidget {
  final RatingAccessOverride adminOverride;
  final bool inert;
  const _OverrideDetails({required this.adminOverride, required this.inert});

  @override
  Widget build(BuildContext context) {
    final reason = adminOverride.reason;
    final updated = ratingAccessUpdatedLine(adminOverride);
    return Padding(
      padding: const EdgeInsets.only(left: 40, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reason != null)
            Text(
              AppStrings.ratingAccessReason(reason),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          if (updated != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                updated,
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ),
          if (inert)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                AppStrings.ratingAccessOverrideInert,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
