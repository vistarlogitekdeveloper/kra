import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/feature_flags.dart';
import 'package:vistar_app/features/hr/presentation/screens/employee_form_screen.dart';

/// Guards the access-role escalation path in the employee form.
///
/// `_canGrantRoles` hides the **Access roles** field, but the **Designation**
/// dropdown beside it was never gated — and `role` was derived from the title
/// unconditionally, then PATCHed whenever it differed from the original. Since
/// `roleFromDesignation` turns "Director" into `HR_ADMIN` (and `MANAGEMENT`
/// once `FeatureFlags.roleTiers` is on), anyone who could edit an employee
/// could grant the top tier by picking a job title — straight around the gate
/// whose stated purpose is to prevent exactly that.
///
/// The rule now PINS access for anyone who may not grant roles: they may
/// retitle someone freely, but never move their access.
void main() {
  group('roleFromDesignation — the title → access default', () {
    test('management titles reach the top tier', () {
      // The escalation target. With roleTiers off this is HR_ADMIN, which the
      // audit found to be the most privileged role in the running system.
      const expected = FeatureFlags.roleTiers ? 'MANAGEMENT' : 'HR_ADMIN';
      for (final title in [
        'Founder & CEO',
        'Director',
        'Chairman',
        'founder & ceo',
      ]) {
        expect(roleFromDesignation(title), expected, reason: title);
      }
    });

    test('other titles map to their functional role', () {
      expect(roleFromDesignation('Senior Officer-Hr'), 'HR');
      expect(roleFromDesignation('Sr. Accountant'), 'FINANCE');
      expect(roleFromDesignation('Commercial Manager'), 'MANAGER');
      expect(roleFromDesignation('Project Incharge'), 'MANAGER');
      expect(roleFromDesignation('Software Developer'), 'EMPLOYEE');
      expect(roleFromDesignation(''), 'EMPLOYEE');
    });
  });

  group('resolveEmployeeRole — who may move access', () {
    test('a user who may NOT grant cannot escalate via the designation', () {
      // The exact attack: pick "Director" and save.
      expect(
        resolveEmployeeRole(
          mayGrantRoles: false,
          designation: 'Director',
          originalRole: 'EMPLOYEE',
        ),
        'EMPLOYEE',
        reason: 'the title changed; access must not',
      );
    });

    test('nor by any other title', () {
      for (final title in [
        'Founder & CEO',
        'Chairman',
        'Senior Officer-Hr',
        'Sr. Accountant',
        'Commercial Manager',
      ]) {
        expect(
          resolveEmployeeRole(
            mayGrantRoles: false,
            designation: title,
            originalRole: 'EMPLOYEE',
          ),
          'EMPLOYEE',
          reason: title,
        );
      }
    });

    test('nor by smuggling an explicit role past the hidden field', () {
      // The Access-roles field is hidden for them, but the payload builder must
      // not honour a value even if one arrives.
      expect(
        resolveEmployeeRole(
          mayGrantRoles: false,
          designation: '',
          explicitRole: 'SUPER_ADMIN',
          originalRole: 'EMPLOYEE',
        ),
        'EMPLOYEE',
      );
    });

    test('nor on CREATE, where there is no original to fall back to', () {
      expect(
        resolveEmployeeRole(
          mayGrantRoles: false,
          designation: 'Director',
          originalRole: null,
        ),
        'EMPLOYEE',
        reason: 'must fail closed to least privilege',
      );
    });

    test('an existing role is PRESERVED, not downgraded', () {
      // Pinning must not silently demote someone either — retitling a manager
      // has to leave them a manager.
      expect(
        resolveEmployeeRole(
          mayGrantRoles: false,
          designation: 'Software Developer',
          originalRole: 'MANAGER',
        ),
        'MANAGER',
      );
    });

    test('a user who MAY grant still gets the designation default', () {
      expect(
        resolveEmployeeRole(
          mayGrantRoles: true,
          designation: 'Commercial Manager',
          originalRole: 'EMPLOYEE',
        ),
        'MANAGER',
      );
    });

    test('an explicit Access role wins for a user who may grant', () {
      expect(
        resolveEmployeeRole(
          mayGrantRoles: true,
          designation: 'Software Developer',
          explicitRole: 'HR_ADMIN',
          originalRole: 'EMPLOYEE',
        ),
        'HR_ADMIN',
        reason: 'title and access are separate axes',
      );
    });

    test('with no designation, a granter keeps the existing role', () {
      expect(
        resolveEmployeeRole(
          mayGrantRoles: true,
          designation: '   ',
          originalRole: 'FINANCE',
        ),
        'FINANCE',
        reason: 'whitespace is not a title',
      );
    });

    test('a granter creating with no designation gets least privilege', () {
      expect(
        resolveEmployeeRole(mayGrantRoles: true, designation: ''),
        'EMPLOYEE',
      );
    });
  });
}
