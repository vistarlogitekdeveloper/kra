/// Which review pipeline an organisation runs.
///
/// Organisations differ in who is expected to rate. The original pipeline is
/// bottom-up — the employee rates themselves, then their reporting manager, HR
/// and Accounts rate in parallel, then management signs off. Some
/// organisations instead want ratings entered centrally, by administrators
/// only, with no self-rating and no manager step.
///
/// [standard] is the DEFAULT and is deliberately implemented as a pass-through:
/// `actorRolesFor` returns `stage.actorRoles` for it — the same object, not a
/// copy — so an organisation on the standard flow gets exactly the role sets it
/// got before flows existed, and every flow-aware gate collapses to its
/// original expression.
///
/// That pass-through is the ONLY guarantee on offer. `ReviewStage` is shared
/// between the two flows and IS edited from time to time (it gained
/// `UserRole.superAdmin` on four stages, for instance) — such a change lands on
/// both flows at once, by design. Do not read the pass-through as "the standard
/// flow is frozen": it means the flow choice adds nothing to it.
enum ReviewFlow {
  /// Self → (reporting manager | HR | Accounts) → management → payout.
  ///
  /// The original pipeline. Every organisation gets this unless it explicitly
  /// opts out, including organisations created before the flow existed and any
  /// whose stored value cannot be read.
  standard,

  /// (HR | Accounts) → management → payout.
  ///
  /// The standard pipeline with EXACTLY two stages removed: the employee's
  /// self-rating and the reporting-manager rating. Those are the two
  /// relationship stages, and taking ratings out of the reporting line is the
  /// whole point of this flow.
  ///
  /// Everything downstream is untouched — HR and Accounts still rate their own
  /// seats, management still signs off, the payout is unchanged. An earlier
  /// version of this comment also claimed the Accounts rating was removed, and
  /// the code matched it, which stranded every Accounts-assigned KRA with no
  /// eligible rater at all.
  adminOnly;

  String toApiString() {
    switch (this) {
      case ReviewFlow.standard:
        return 'STANDARD';
      case ReviewFlow.adminOnly:
        return 'ADMIN_ONLY';
    }
  }

  /// Tolerant, and biased towards [standard].
  ///
  /// An unknown or absent value means standard, NOT an error: organisations
  /// predate this field, and a server that has not shipped the column yet
  /// simply omits it. Failing closed to the original pipeline is the only safe
  /// default — guessing [adminOnly] would silently strip every employee's
  /// ability to rate themselves.
  static ReviewFlow fromApi(String? value) {
    switch ((value ?? '').trim().toUpperCase()) {
      case 'ADMIN_ONLY':
      case 'ADMIN':
        return ReviewFlow.adminOnly;
      case 'STANDARD':
      default:
        return ReviewFlow.standard;
    }
  }

  String get displayName {
    switch (this) {
      case ReviewFlow.standard:
        return 'Standard';
      case ReviewFlow.adminOnly:
        return 'Administrators only';
    }
  }

  String get description {
    switch (this) {
      case ReviewFlow.standard:
        return 'The employee rates themselves, then their reporting manager, '
            'HR and Accounts rate their assigned KRAs, then management signs '
            'off.';
      case ReviewFlow.adminOnly:
        return 'Only HR, management and admins enter ratings. Employees do not '
            'self-rate and reporting managers do not rate.';
    }
  }
}
