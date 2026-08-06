import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/router/app_router.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

/// One post can carry several responsibilities — the commercial/HR-admin who
/// also rates the Accounts seat — which a single role cannot express. These
/// cover the union behaviour, and the two invariants that keep the widening
/// safe: a role-less payload still resolves, and granting access is a tier
/// above administering employees.
void main() {
  User user({
    UserRole role = UserRole.employee,
    Set<UserRole> roles = const {},
  }) =>
      User(
        id: 'u1',
        email: 'a@b.test',
        fullName: 'Asha',
        role: role,
        roles: roles,
        organizationId: 'org1',
      );

  group('User.effectiveRoles', () {
    test('falls back to the scalar role when no roles array is sent — the '
        'current API shape, so nothing changes for existing users', () {
      final u = user(role: UserRole.hrAdmin);
      expect(u.effectiveRoles, {UserRole.hrAdmin});
      expect(u.hasRole(UserRole.hrAdmin), isTrue);
      expect(u.hasRole(UserRole.finance), isFalse);
    });

    test('includes the primary role even if the array omits it', () {
      final u = user(role: UserRole.hrAdmin, roles: {UserRole.finance});
      expect(u.effectiveRoles, {UserRole.hrAdmin, UserRole.finance});
    });

    test('hasAnyRole is the union — either seat is enough', () {
      final u = user(role: UserRole.hrAdmin, roles: {UserRole.finance});
      expect(u.hasAnyRole({UserRole.finance}), isTrue);
      expect(u.hasAnyRole({UserRole.manager, UserRole.hr}), isFalse);
    });
  });

  group('User.fromJson multi-role', () {
    test('reads a roles array', () {
      final u = User.fromJson({
        'id': 'u1',
        'email': 'a@b.test',
        'fullName': 'Asha',
        'role': 'HR_ADMIN',
        'roles': ['HR_ADMIN', 'FINANCE'],
        'organizationId': 'org1',
      });
      expect(u.role, UserRole.hrAdmin);
      expect(u.effectiveRoles, {UserRole.hrAdmin, UserRole.finance});
    });

    test('MANAGEMENT resolves instead of silently demoting to EMPLOYEE — the '
        'founder must not lose review access when the backend ships it', () {
      final u = User.fromJson({
        'id': 'u1',
        'email': 'a@b.test',
        'fullName': 'Prashant',
        'role': 'MANAGEMENT',
        'organizationId': 'org1',
      });
      expect(u.role, UserRole.management);
    });

    test('a roles array alone still yields a usable primary role', () {
      final u = User.fromJson({
        'id': 'u1',
        'email': 'a@b.test',
        'fullName': 'Asha',
        'roles': ['FINANCE'],
        'organizationId': 'org1',
      });
      expect(u.effectiveRoles, contains(UserRole.finance));
    });
  });

  // Granting roles is a privilege-escalation path: an HR admin who could edit
  // access could promote themselves. It stays a tier above them.
  group('User.isSuperAdmin', () {
    test('only the admin tier may change access', () {
      expect(user(role: UserRole.admin).isSuperAdmin, isTrue);
      expect(user(role: UserRole.hrAdmin).isSuperAdmin, isFalse);
      expect(user(role: UserRole.management).isSuperAdmin, isFalse);
      expect(user(role: UserRole.hr).isSuperAdmin, isFalse);
    });

    test('SUPER_ADMIN from the wire maps onto that tier', () {
      final u = User.fromJson({
        'id': 'u1',
        'email': 'a@b.test',
        'fullName': 'Swati',
        'role': 'SUPER_ADMIN',
        'organizationId': 'org1',
      });
      expect(u.isSuperAdmin, isTrue);
    });
  });

  group('workspace access is the union of held roles', () {
    test('HR admin + Accounts reaches both the HR console and Reviews', () {
      final roles = {UserRole.hrAdmin, UserRole.finance};
      expect(AppRoutes.canAccessHrAny(roles), isTrue);
      expect(AppRoutes.canReviewAny(roles), isTrue);
    });

    test('a role that grants nothing on its own still grants via the other', () {
      // Employee alone reaches no admin area; paired with FINANCE it reviews.
      expect(AppRoutes.canReviewAny({UserRole.employee}), isFalse);
      expect(AppRoutes.canReviewAny({UserRole.employee, UserRole.finance}),
          isTrue);
      // ...but reviewing is still not the HR console.
      expect(AppRoutes.canAccessHrAny({UserRole.employee, UserRole.finance}),
          isFalse);
    });

    test('Management reviews but does NOT administer employees', () {
      expect(AppRoutes.canReviewAny({UserRole.management}), isTrue);
      expect(AppRoutes.canAccessHrAny({UserRole.management}), isFalse);
    });
  });

  group('ReviewStage.isActionableByAny', () {
    test('holding HR + Accounts can act on either Review seat', () {
      final roles = {UserRole.hrAdmin, UserRole.finance};
      expect(ReviewStage.accountHrRating.isActionableByAny(roles), isTrue);
      expect(ReviewStage.financeRating.isActionableByAny(roles), isTrue);
    });

    test('Management holds the management seat', () {
      expect(
        ReviewStage.managementReview.isActionableByAny({UserRole.management}),
        isTrue,
      );
    });

    test('no held role grants a seat nobody owns', () {
      expect(
        ReviewStage.managementReview
            .isActionableByAny({UserRole.employee, UserRole.manager}),
        isFalse,
      );
    });
  });
}
