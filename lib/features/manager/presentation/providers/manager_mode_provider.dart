import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/enums.dart';

/// Top-level toggle between "My Team" and "My Review" inside the
/// manager shell. Lives at module scope (not autoDispose) so the
/// selection survives across rebuilds when the user navigates between
/// sub-routes.
///
/// `IndexedStack` in the outer shell keeps both subtrees alive, so
/// switching modes preserves each one's nav stack — this provider
/// just owns which index is on top.
class ManagerModeNotifier extends StateNotifier<ManagerMode> {
  ManagerModeNotifier() : super(ManagerMode.myTeam);

  void setMode(ManagerMode mode) => state = mode;
  void toMyTeam() => state = ManagerMode.myTeam;
  void toMyReview() => state = ManagerMode.myReview;
  void toggle() => state = state == ManagerMode.myTeam
      ? ManagerMode.myReview
      : ManagerMode.myTeam;
}

final managerModeProvider =
    StateNotifierProvider<ManagerModeNotifier, ManagerMode>(
  (ref) => ManagerModeNotifier(),
);
