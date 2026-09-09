import '../../../../core/enums/review_flow.dart';
import '../../../auth/data/models/user.dart';
import 'review_stage.dart';

/// Who may act on [stage] under [flow].
///
/// The single place the two pipelines diverge. For [ReviewFlow.standard] this
/// returns [ReviewStage.actorRoles] verbatim — same object, same values — so
/// the original pipeline is not merely equivalent but identical. Edits to
/// [ReviewStage] itself therefore reach BOTH flows; only the divergence below
/// is flow-specific.
///
/// An empty set means the stage is NOT PART of the flow: nobody can act on it,
/// which is how [ReviewFlow.adminOnly] removes the self-rating and the
/// reporting-manager rating — and nothing else.
Set<UserRole> actorRolesFor(ReviewStage stage, ReviewFlow flow) {
  if (flow == ReviewFlow.standard) return stage.actorRoles;

  switch (stage) {
    // The ONLY stage admin-only removes. Ratings are entered centrally, so
    // there is no self-assessment to enter and nobody may enter one.
    case ReviewStage.selfRating:
      return const {};

    // NOT removed — REASSIGNED.
    //
    // In the standard pipeline this seat belongs to the employee's own
    // reporting manager, as a relationship. Under admin-only it belongs to
    // MANAGEMENT, as a role: HR and Accounts rate the KRAs assigned to them,
    // and management rates everything left over — the KRAs pointing at the
    // reporting manager, and any with no assignment at all.
    //
    // Keeping the stage rather than deleting it is what makes the arithmetic
    // come out right. Every KRA still resolves to a Review score through its
    // own assigned stage, so no row drops out of `reviewWeightedPct`, and a
    // KRA's weight cannot silently redistribute itself across the others.
    // Deleting the stage instead left those rows unrateable, which is exactly
    // the hole this closes.
    //
    // Derived from the sign-off's own actors so the two cannot drift, and so
    // the FeatureFlags.roleTiers narrowing applies here for free.
    case ReviewStage.reportingManagerRating:
      return ReviewStage.managementReview.actorRoles;

    // Everything else is UNCHANGED from the standard pipeline: the HR rating,
    // the Accounts rating, the management sign-off and the payout all keep
    // exactly their normal actors.
    //
    // Derived rather than restated on purpose. An earlier version listed the
    // roles by hand here, which (a) dropped Accounts entirely — so an
    // Accounts-assigned KRA had no rater at all — and (b) hardcoded hrAdmin
    // into the sign-off, bypassing the FeatureFlags.roleTiers narrowing and
    // letting HR approve its own HR rating. Deferring to the stage cannot
    // drift from it.
    default:
      return stage.actorRoles;
  }
}

/// Whether [stage]'s actor is decided by a RELATIONSHIP to this particular
/// review — its owner, or its reporting manager — rather than by the actor's
/// role, under [flow].
///
/// The distinction is not cosmetic: a relationship stage must be checked
/// against `employeeId` / `managerId`, and a role stage against the caller's
/// roles. Asking the wrong question locks out the right person.
///
/// [ReviewStage.selfRating] is always the review's owner, in every flow that
/// has it at all. [ReviewStage.reportingManagerRating] is the one that moves:
/// the reporting manager under [ReviewFlow.standard], and management-as-a-role
/// under [ReviewFlow.adminOnly], whose whole purpose is to take rating out of
/// the reporting line.
bool stageIsRelationshipGated(ReviewStage stage, ReviewFlow flow) {
  switch (stage) {
    case ReviewStage.selfRating:
      return true;
    case ReviewStage.reportingManagerRating:
      return flow == ReviewFlow.standard;
    default:
      return false;
  }
}

/// Whether [stage] is used at all under [flow].
bool stageIsInFlow(ReviewStage stage, ReviewFlow flow) {
  if (flow == ReviewFlow.standard) return true;
  return actorRolesFor(stage, flow).isNotEmpty;
}

/// Whether any of [roles] may act on [stage] under [flow].
bool canActOnStage(ReviewStage stage, ReviewFlow flow, Set<UserRole> roles) {
  final allowed = actorRolesFor(stage, flow);
  if (allowed.isEmpty) return false;
  return roles.intersection(allowed).isNotEmpty;
}
