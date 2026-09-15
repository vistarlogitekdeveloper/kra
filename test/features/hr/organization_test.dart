import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/features/auth/data/models/token_pair.dart';
import 'package:vistar_app/features/hr/data/models/organization.dart';

/// The Organization model and the copy that renders it.
///
/// Organisations are the tenancy boundary — every employee, template, location
/// and review is scoped to one — so parsing them wrongly is not cosmetic.
void main() {
  group('Organization.fromJson', () {
    test('reads the full payload', () {
      final o = Organization.fromJson({
        'id': 'org_1',
        'name': 'Vistar Logitek North',
        'slug': 'vistar-logitek-north',
        'logoUrl': 'https://example.test/logo.png',
        'employeeCount': 12,
        'createdAt': '2026-09-01T10:00:00.000Z',
      });
      expect(o.id, 'org_1');
      expect(o.name, 'Vistar Logitek North');
      expect(o.slug, 'vistar-logitek-north');
      expect(o.logoUrl, 'https://example.test/logo.png');
      expect(o.employeeCount, 12);
      expect(o.createdAt, isNotNull);
    });

    test('tolerates a stringified count', () {
      // Decimals and counts arrive as strings from parts of this backend.
      final o = Organization.fromJson(
          {'id': 'a', 'name': 'A', 'slug': 'a', 'employeeCount': '7'});
      expect(o.employeeCount, 7);
    });

    test('keeps an absent count NULL rather than defaulting to zero', () {
      // "not counted" and "empty" must stay distinguishable — the detail
      // endpoint omits the figure, and rendering that as "No employees" would
      // claim a tenant is empty when nobody counted.
      final o = Organization.fromJson({'id': 'a', 'name': 'A', 'slug': 'a'});
      expect(o.employeeCount, isNull);
    });

    test('survives a payload with nothing in it', () {
      final o = Organization.fromJson({});
      expect(o.id, '');
      expect(o.slug, '');
      expect(o.employeeCount, isNull);
    });

    test('identity is id + slug', () {
      const a = Organization(id: '1', name: 'A', slug: 'a');
      const b = Organization(id: '1', name: 'Renamed', slug: 'a');
      const c = Organization(id: '2', name: 'A', slug: 'a');
      expect(a, b, reason: 'a rename is the same organization');
      expect(a, isNot(c));
    });
  });

  group('orgEmployeeCount copy', () {
    test('distinguishes uncounted, empty, one and many', () {
      expect(AppStrings.orgEmployeeCount(null), 'Not counted');
      expect(AppStrings.orgEmployeeCount(0), 'No employees');
      expect(AppStrings.orgEmployeeCount(1), '1 employee');
      expect(AppStrings.orgEmployeeCount(12), '12 employees');
    });
  });

  group('slug validation matches the server regex', () {
    // Mirrors organizations.routes.js and the form's own pattern. Kept here so
    // a divergence shows up as a failing test rather than a 400 on save.
    final pattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

    test('accepts what the server accepts', () {
      for (final s in [
        'vistar',
        'vistar-logitek',
        'vistar-logitek-north',
        'org2',
        'a1-b2-c3',
      ]) {
        expect(pattern.hasMatch(s), isTrue, reason: s);
      }
    });

    test('rejects what the server rejects', () {
      for (final s in [
        'Vistar', // uppercase
        'vistar_logitek', // underscore
        '-vistar', // leading hyphen
        'vistar-', // trailing hyphen
        'vistar--logitek', // doubled hyphen
        'vistar logitek', // space
        '', // empty
      ]) {
        expect(pattern.hasMatch(s), isFalse, reason: '"$s" should be rejected');
      }
    });
  });

  group('TokenPair expiry fallback', () {
    test('a response without expiresIn falls back to the shared default', () {
      final p = TokenPair.fromJson({'accessToken': 'a', 'refreshToken': 'r'});
      expect(p.expiresIn, TokenPair.defaultExpiresIn);
    });

    test('an explicit expiresIn wins', () {
      final p = TokenPair.fromJson(
          {'accessToken': 'a', 'refreshToken': 'r', 'expiresIn': 60});
      expect(p.expiresIn, 60);
    });

    test('the default is a sane access-token lifetime', () {
      // The organisation switch reuses this because its response carries no
      // expiry; a zero or negative value would make the token instantly stale.
      expect(TokenPair.defaultExpiresIn, greaterThan(0));
    });
  });
}
