import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

/// Two review pipelines, one of which must not change.
///
/// The standard flow — self → (manager | HR | Accounts) → management → payout —
/// is in production and working. The admin-only flow is new. The whole design
/// rests on `actorRolesFor(stage, standard)` being a pass-through to
/// `ReviewStage.actorRoles`, so the first group here is the important one: it
/// pins that the original pipeline is IDENTICAL, not merely similar.
void main() {
  group('the standard flow is untouched', () {
    test('actorRolesFor returns ReviewStage.actorRoles for every stage', () {
      for (final stage in ReviewStage.values) {
        expect(
          actorRolesFor(stage, ReviewFlow.standard),
          same(stage.actorRoles),
          reason: 'stage ${stage.name} must pass through unchanged — not a '
              'copy, the same set',
        );
      }
    });

    test('every stage is part of the standard flow', () {
      for (final stage in ReviewStage.values) {
        expect(stageIsInFlow(stage, ReviewFlow.standard), isTrue,
            reason: stage.name);
      }
    });

    test('canActOnStage agrees with the original isActionableByAny', () {
      // Belt and braces: the new entry point must answer exactly what the old
      // one did, for every stage and every role.
      for (final stage in ReviewStage.values) {
        for (final role in UserRole.values) {
          expect(
            canActOnStage(stage, ReviewFlow.standard, {role}),
            stage.isActionableByAny({role}),
            reason: '${stage.name} / ${role.name}',
          );
        }
      }
    });

    test('is what an unknown or missing value resolves to', () {
      // Organisations predate this field, and a server without the column
      // omits it. Guessing adminOnly would silently strip every employee's
      // self-rating, so the fallback has to be standard.
      expect(ReviewFlow.fromApi(null), ReviewFlow.standard);
      expect(ReviewFlow.fromApi(''), ReviewFlow.standard);
      expect(ReviewFlow.fromApi('   '), ReviewFlow.standard);
      expect(ReviewFlow.fromApi('SOMETHING_NEW'), ReviewFlow.standard);
      expect(ReviewFlow.fromApi('STANDARD'), ReviewFlow.standard);
    });
  });

  group('the admin-only flow', () {
    test('removes EXACTLY ONE stage: the self-rating', () {
      expect(
          actorRolesFor(ReviewStage.selfRating, ReviewFlow.adminOnly), isEmpty);
      expect(
          stageIsInFlow(ReviewStage.selfRating, ReviewFlow.adminOnly), isFalse);
    });

    test('the manager seat is REASSIGNED to management, not removed', () {
      // It was briefly removed. That left every KRA assigned to the reporting
      // manager — and every KRA never assigned at all, since rows default to
      // that seat — with no rater whatsoever, and silently redistributed their
      // weight across the remaining KRAs when the totals renormalised.
      //
      // The rule instead: HR and Accounts rate what they are assigned, and
      // management rates the remainder.
      expect(
          stageIsInFlow(
              ReviewStage.reportingManagerRating, ReviewFlow.adminOnly),
          isTrue);
      expect(
        actorRolesFor(ReviewStage.reportingManagerRating, ReviewFlow.adminOnly),
        same(ReviewStage.managementReview.actorRoles),
        reason: 'derived from the sign-off actors so the two cannot drift, and '
            'so FeatureFlags.roleTiers narrows both at once',
      );
    });

    test('EVERY stage keeps an actor except the self-rating', () {
      // The invariant that stops a KRA becoming unratable.
      for (final stage in ReviewStage.values) {
        if (stage == ReviewStage.selfRating || stage == ReviewStage.completed) {
          continue;
        }
        expect(actorRolesFor(stage, ReviewFlow.adminOnly), isNotEmpty,
            reason: stage.name);
      }
    });

    test('removes NOTHING else — every other stage keeps its standard actors',
        () {
      // An earlier version also dropped the Accounts rating, which left every
      // Accounts-assigned KRA with no eligible rater at all. Deriving from the
      // stage instead of restating a role list is what fixed it; this pins
      // that only the two relationship stages differ from standard.
      for (final stage in ReviewStage.values) {
        if (stage == ReviewStage.selfRating ||
            stage == ReviewStage.reportingManagerRating) {
          continue;
        }
        expect(
          actorRolesFor(stage, ReviewFlow.adminOnly),
          same(stage.actorRoles),
          reason: '${stage.name} must be untouched by the flow',
        );
      }
    });

    test('Accounts keeps its rating seat', () {
      expect(
        canActOnStage(ReviewStage.financeRating, ReviewFlow.adminOnly,
            {UserRole.finance}),
        isTrue,
      );
    });

    test('nobody at all can act on a removed stage', () {
      for (final role in UserRole.values) {
        expect(
          canActOnStage(ReviewStage.selfRating, ReviewFlow.adminOnly, {role}),
          isFalse,
          reason: 'role ${role.name} must not self-rate in this flow',
        );
      }
    });

    test('HR keeps its rating seat', () {
      expect(
        canActOnStage(
            ReviewStage.accountHrRating, ReviewFlow.adminOnly, {UserRole.hr}),
        isTrue,
      );
    });

    test('the sign-off honours FeatureFlags.roleTiers, not a hardcoded list',
        () {
      // Restating the roles here previously hardcoded hrAdmin into the
      // sign-off, bypassing the roleTiers narrowing and letting HR approve its
      // own HR rating.
      expect(
        actorRolesFor(ReviewStage.managementReview, ReviewFlow.adminOnly),
        same(ReviewStage.managementReview.actorRoles),
      );
    });

    test('an ordinary employee can rate nothing', () {
      for (final stage in ReviewStage.values) {
        expect(
          canActOnStage(stage, ReviewFlow.adminOnly, {UserRole.employee}),
          isFalse,
          reason: 'employee must not act on ${stage.name}',
        );
      }
    });

    test('the MANAGER role loses its rating seat', () {
      // The whole point of the flow: ratings leave the reporting LINE. The
      // reporting-manager STAGE survives — management holds it — but a line
      // manager holding no other role still rates nothing, including that
      // stage, which now bears their name in title only.
      for (final stage in ReviewStage.values) {
        expect(
          canActOnStage(stage, ReviewFlow.adminOnly, {UserRole.manager}),
          isFalse,
          reason: 'manager must not act on ${stage.name}',
        );
      }
    });

    test('MANAGEMENT rates the remainder AND signs off', () {
      for (final stage in [
        ReviewStage.reportingManagerRating,
        ReviewStage.managementReview,
      ]) {
        expect(
          canActOnStage(stage, ReviewFlow.adminOnly, {UserRole.management}),
          isTrue,
          reason: stage.name,
        );
      }
      // But it does not take over HR's or Accounts' own rows.
      for (final stage in [
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
      ]) {
        expect(
          canActOnStage(stage, ReviewFlow.adminOnly, {UserRole.management}),
          isFalse,
          reason: stage.name,
        );
      }
    });

    test('payout is left alone — settlement is not rating', () {
      // Narrowing this would strand incentives as computed-but-unmarked.
      expect(
        actorRolesFor(ReviewStage.incentivePayout, ReviewFlow.adminOnly),
        ReviewStage.incentivePayout.actorRoles,
      );
    });

    test('the terminal stage has no actor in either flow', () {
      expect(
          actorRolesFor(ReviewStage.completed, ReviewFlow.adminOnly), isEmpty);
      expect(ReviewStage.completed.actorRoles, isEmpty);
    });
  });

  group('wire round-trip', () {
    test('every flow round-trips', () {
      for (final f in ReviewFlow.values) {
        expect(ReviewFlow.fromApi(f.toApiString()), f, reason: f.name);
      }
    });

    test('the wire forms are the values the API stores', () {
      expect(ReviewFlow.standard.toApiString(), 'STANDARD');
      expect(ReviewFlow.adminOnly.toApiString(), 'ADMIN_ONLY');
    });

    test('every flow has a name and a description for the picker', () {
      for (final f in ReviewFlow.values) {
        expect(f.displayName, isNotEmpty, reason: f.name);
        expect(f.description, isNotEmpty, reason: f.name);
      }
    });
  });
}
