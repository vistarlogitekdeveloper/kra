import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';

/// `/auth/me` must not ERASE what `/auth/login` established.
///
/// The two endpoints build their user payloads from separate code on the
/// server, so they drift. That would be harmless if the client merged them —
/// but `refreshCurrentUser` REPLACES the stored user with the `/auth/me`
/// response wholesale, and the client rebuilds its session from that on every
/// boot, page reload and organisation switch (adoptTokens calls it directly).
///
/// So a field only `login` returns does not merely go missing on refresh. It is
/// destroyed, and every parser default takes over. The live instance:
/// `reviewFlow` was added to login and not to getMe, `ReviewFlow.fromApi(null)`
/// resolves to [ReviewFlow.standard], and an organisation switched to
/// administrators-only reverted to the standard pipeline seconds after login —
/// leaving HR unable to rate anything, because the sheet was waiting on a
/// self-rating that flow removes. Nothing on screen said the flow had changed.
///
/// Fixed on the server too (docs/install_review_flow.mjs edit 2b). This guards
/// the client half, which is what protects users of a deployment that has not
/// taken that patch.
void main() {
  final repoSource = File(
    'lib/features/auth/data/repositories/api_auth_repository.dart',
  ).readAsStringSync();

  /// `refreshCurrentUser`'s body, isolated so the assertions cannot be
  /// satisfied by some unrelated part of the file.
  String refreshCurrentUserBody() {
    const marker = 'Future<User?> refreshCurrentUser() async {';
    final start = repoSource.indexOf(marker);
    expect(start, greaterThan(-1),
        reason: 'refreshCurrentUser has been renamed — retarget this test '
            'rather than deleting it; the hazard it guards has not gone away');
    // To the next top-level member, which is enough to cover the method.
    final end = repoSource.indexOf('\n  /// ', start + marker.length);
    return repoSource.substring(start, end == -1 ? repoSource.length : end);
  }

  group('the parsing default that made this dangerous', () {
    test('an absent reviewFlow silently becomes standard', () {
      // Not a complaint about the default — failing to the original pipeline is
      // the right call when the value is genuinely unknown. It is WHY a dropped
      // field is invisible: there is no error, no null, just the wrong flow.
      expect(ReviewFlow.fromApi(null), ReviewFlow.standard);
      expect(ReviewFlow.fromApi(''), ReviewFlow.standard);

      final withoutFlow = User.fromJson(const {
        'id': 'u1',
        'email': 'hr@vistar.test',
        'name': 'HR',
        'role': 'HR',
        'organizationId': 'org1',
      });
      expect(withoutFlow.reviewFlow, ReviewFlow.standard,
          reason: 'a payload with no reviewFlow yields the standard pipeline, '
              'which is exactly how an ADMIN_ONLY organisation reverted');
    });

    test('an explicit value still wins, so a flow can be changed back', () {
      // The preservation below must not pin a stale flow: a server that has the
      // field always sends one, STANDARD included.
      final u = User.fromJson(const {
        'id': 'u1',
        'email': 'hr@vistar.test',
        'name': 'HR',
        'role': 'HR',
        'organizationId': 'org1',
        'reviewFlow': 'ADMIN_ONLY',
      });
      expect(u.reviewFlow, ReviewFlow.adminOnly);
      expect(ReviewFlow.fromApi('STANDARD'), ReviewFlow.standard);
    });
  });

  group('refreshCurrentUser must not parse the raw /auth/me payload', () {
    test('it routes the response through the preserving merge', () {
      final body = refreshCurrentUserBody();
      expect(
        body.contains('_withPreservedReviewFlow'),
        isTrue,
        reason: 'refreshCurrentUser is parsing /auth/me directly again. Any '
            'field login sends and /auth/me omits is now ERASED on the next '
            'boot, reload or org switch — see this file\'s doc comment.',
      );
    });

    test('it does not parse unwrapObject(response) straight into a User', () {
      final body = refreshCurrentUserBody();
      final collapsed = body.replaceAll(RegExp(r'\s+'), '');
      expect(
        collapsed.contains('User.fromJson(unwrapObject(response))'),
        isFalse,
        reason: 'the exact shape of the original bug: the raw /auth/me body '
            'parsed with no merge, discarding whatever it did not carry',
      );
    });

    test('what gets STORED is the merged map, not the raw response', () {
      // Preserving the value in memory but writing the raw payload to storage
      // would move the bug one boot later instead of fixing it: the next cold
      // start reads the file back.
      final body = refreshCurrentUserBody();
      final collapsed = body.replaceAll(RegExp(r'\s+'), '');
      expect(
        collapsed.contains('writeUserJson(unwrapObject(response))'),
        isFalse,
        reason: 'storage must receive the merged map, or the erasure simply '
            'happens on the following cold start',
      );
      expect(collapsed.contains('writeUserJson(userJson)'), isTrue,
          reason: 'store the same map that was parsed');
    });
  });

  group('the merge only fills in ABSENCE', () {
    test('it keys on a non-empty string, so an explicit value is respected',
        () {
      // Pinned against the source because the distinction is the whole safety
      // argument: treat any incoming value as authoritative, and treat only a
      // missing/blank one as "unknown, keep what we were last told".
      const marker = 'Future<Map<String, dynamic>> _withPreservedReviewFlow';
      final start = repoSource.indexOf(marker);
      expect(start, greaterThan(-1),
          reason: 'the preserving merge has been removed or renamed');
      final body = repoSource.substring(start);
      final collapsed = body.replaceAll(RegExp(r'\s+'), '');
      expect(
        collapsed.contains("incomingisString&&incoming.trim().isNotEmpty"),
        isTrue,
        reason: 'the merge must return the fresh payload untouched whenever it '
            'carries any value at all — otherwise switching an organisation '
            'back to STANDARD would never take effect',
      );
      expect(collapsed.contains('readUserJson()'), isTrue,
          reason: 'the previous value has to come from somewhere');
    });
  });
}
