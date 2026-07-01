import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/router/app_router.dart';
import 'package:vistar_app/features/hr/presentation/screens/hr_home_screen.dart';

/// Pins the action-item key → route mapping for the HR dashboard's
/// "Needs your attention" section. The live `/hr/dashboard/action-items`
/// endpoint emits `hr_feed_missing` and `draft_stuck` today — both used
/// to fall through to the "Coming soon" snackbar because they were absent
/// from the key map. Lock the live keys in here so they can't quietly
/// regress.
void main() {
  group('routeForActionKey — live backend keys', () {
    test('hr_feed_missing → reviews (current backend key)', () {
      expect(routeForActionKey('hr_feed_missing'), AppRoutes.hrReviews);
    });

    test('draft_stuck → reviews (current backend key)', () {
      expect(routeForActionKey('draft_stuck'), AppRoutes.hrReviews);
    });

    test('normalises case — UPPER and lower forms map identically', () {
      expect(
        routeForActionKey('HR_FEED_MISSING'),
        routeForActionKey('hr_feed_missing'),
      );
      expect(
        routeForActionKey('Draft_Stuck'),
        routeForActionKey('DRAFT_STUCK'),
      );
    });
  });

  group('routeForActionKey — known sibling keys route to a real screen', () {
    final reviewScoped = [
      'PENDING_REVIEWS',
      'OVERDUE_REVIEWS',
      'UNFINALIZED_REVIEWS',
      'MANAGER_REVIEW_OVERDUE',
      'OPS_SCORING_OVERDUE',
      'FINANCE_SCORING_OVERDUE',
      'FINALIZATION_OVERDUE',
      'MISSING_BONUS_SLABS',
    ];
    for (final key in reviewScoped) {
      test('$key → reviews', () {
        expect(routeForActionKey(key), AppRoutes.hrReviews);
      });
    }

    test('UNASSIGNED_EMPLOYEES → employees', () {
      expect(routeForActionKey('UNASSIGNED_EMPLOYEES'), AppRoutes.hrEmployees);
    });

    test('INACTIVE_EMPLOYEES → employees', () {
      expect(routeForActionKey('INACTIVE_EMPLOYEES'), AppRoutes.hrEmployees);
    });

    test('MISSING_KRA_TEMPLATES → templates', () {
      expect(routeForActionKey('MISSING_KRA_TEMPLATES'), AppRoutes.hrTemplates);
    });

    test('AUDIT_REVIEW_REQUIRED → audit log', () {
      expect(routeForActionKey('AUDIT_REVIEW_REQUIRED'), AppRoutes.hrAuditLog);
    });
  });

  group('routeForActionKey — unmapped', () {
    test('unknown key returns null so caller can show graceful fallback', () {
      expect(routeForActionKey('some_future_key'), isNull);
      expect(routeForActionKey(''), isNull);
    });
  });
}
