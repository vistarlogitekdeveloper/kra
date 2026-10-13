import 'package:flutter/material.dart';

import '../../../../../core/constants/app_strings.dart';
import 'rating_access_message.dart';

/// What anyone but a super admin sees on the rating-access screen. The router
/// bounces them first; this covers a role that changes under an open screen.
class RatingAccessLocked extends StatelessWidget {
  const RatingAccessLocked({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: const RatingAccessMessage(
            icon: Icons.lock_outline_rounded,
            title: AppStrings.ratingAccessTitle,
            message: AppStrings.ratingAccessLocked,
          ),
        ),
      ),
    );
  }
}
