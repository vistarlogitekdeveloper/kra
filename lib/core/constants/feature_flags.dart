/// Compile-time switches for backend capabilities the client is ready for but
/// the server does not offer yet.
///
/// Same approach as `MONTHLY_BACKEND` in the reviews module: the client carries
/// the finished behaviour behind a `--dart-define`, so turning it on is a
/// deploy-day config change rather than a code edit, review and release.
///
/// Every flag defaults to **false** = today's live behaviour. Flipping one must
/// never be needed to keep the app working; it only unlocks the target state.
/// Because these are `const`, the unused branch is tree-shaken out.
///
/// See `docs/ACCESS_CONTROL_DESIGN.md` §8 for the rollout order, and
/// `docs/BACKEND_CHANGE_REQUEST.md` for the server work each flag waits on.
class FeatureFlags {
  const FeatureFlags._();

  /// The backend's employees role enum accepts `MANAGEMENT` and `SUPER_ADMIN`,
  /// and returns them from `/auth/login` + `/auth/me`.
  ///
  /// Off (today): management sign-off is held by `HR_ADMIN` as well, because
  /// `MANAGEMENT` cannot be assigned to anyone — gating the stage on it alone
  /// would leave it with **no eligible actor**. Management job titles therefore
  /// derive `HR_ADMIN`, and role granting stays open to HR admins, since nobody
  /// can hold the super-admin tier that is meant to own it.
  ///
  /// On: management sign-off becomes exclusive to `MANAGEMENT`, management
  /// titles derive it, and only the super admin may grant roles.
  ///
  ///     flutter run --dart-define=ROLE_TIERS=true
  ///
  /// Turn this on ONLY AFTER the management users have actually been assigned
  /// `MANAGEMENT` — flipping it first takes management review offline.
  static const bool roleTiers =
      bool.fromEnvironment('ROLE_TIERS', defaultValue: false);

  /// The backend accepts and returns a `roles` array alongside the scalar
  /// `role`, so one person can hold several access roles.
  ///
  /// Off (today): the employee form still lets HR pick several roles, but only
  /// the first is persisted — sending an unrecognised `roles` field risks a 400
  /// on *every* save, including ordinary single-role ones.
  ///
  /// On: the full set is sent as `roles`, with the first also sent as `role` for
  /// backward compatibility.
  ///
  ///     flutter run --dart-define=MULTI_ROLE=true
  static const bool multiRole =
      bool.fromEnvironment('MULTI_ROLE', defaultValue: false);
}
