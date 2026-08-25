import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/models/kra_template.dart';

/// Guards the name suggested for a duplicated template.
///
/// The clone endpoint REQUIRES a name (`z.string().min(1).max(200)`) and
/// rejects a duplicate with 409, so a fixed "(Copy)" suffix breaks the second
/// time anyone duplicates the same template — which is the normal case when
/// templates are cloned to carve out per-employee exceptions.
void main() {
  test('the first copy is "(Copy)"', () {
    expect(
      suggestedCloneName('Site Manager', const ['Site Manager']),
      'Site Manager (Copy)',
    );
  });

  test('a taken copy name is numbered, not reused', () {
    expect(
      suggestedCloneName(
          'Site Manager', const ['Site Manager', 'Site Manager (Copy)']),
      'Site Manager (Copy 2)',
    );
    expect(
      suggestedCloneName('Site Manager', const [
        'Site Manager',
        'Site Manager (Copy)',
        'Site Manager (Copy 2)',
      ]),
      'Site Manager (Copy 3)',
    );
  });

  test('a gap in the numbering is filled rather than skipped past', () {
    // "(Copy)" is free again after a delete — reuse it instead of climbing.
    expect(
      suggestedCloneName(
          'Site Manager', const ['Site Manager', 'Site Manager (Copy 2)']),
      'Site Manager (Copy)',
    );
  });

  test('matching ignores case and surrounding space, which the server does not',
      () {
    // Stricter than the server (its uniqueness check is exact), and erring this
    // way can only suggest a MORE distinct name — never a colliding one.
    expect(
      suggestedCloneName('Site Manager', const ['  site manager (copy) ']),
      'Site Manager (Copy 2)',
    );
  });

  test('an empty list is fine — nothing is taken', () {
    expect(suggestedCloneName('Ops Head', const []), 'Ops Head (Copy)');
  });

  group('the API length cap', () {
    test('a suggestion never exceeds it', () {
      final long = 'A' * kKraTemplateNameMaxLength;
      final name = suggestedCloneName(long, const []);
      expect(name.length, lessThanOrEqualTo(kKraTemplateNameMaxLength));
    });

    test('the BASE is trimmed, so the suffix survives intact', () {
      // A name ending in a half-written "(Cop" reads as corruption, and the
      // suffix is the part that makes the name unique.
      final long = 'A' * kKraTemplateNameMaxLength;
      final first = suggestedCloneName(long, const []);
      expect(first, endsWith(' (Copy)'));
      expect(first.length, lessThanOrEqualTo(kKraTemplateNameMaxLength));
      // Feed the trimmed suggestion back as taken: the next one must still
      // carry a whole suffix, and still fit.
      final second = suggestedCloneName(long, [first]);
      expect(second, endsWith(' (Copy 2)'));
      expect(second.length, lessThanOrEqualTo(kKraTemplateNameMaxLength));
    });

    test('numbering still terminates when every short suffix is taken', () {
      final base = 'B' * kKraTemplateNameMaxLength;
      final taken = [
        for (var n = 1; n <= 5; n++)
          suggestedCloneName(base, [
            for (var k = 1; k < n; k++) 'placeholder$k',
          ]),
      ];
      final name = suggestedCloneName(base, taken);
      expect(name.length, lessThanOrEqualTo(kKraTemplateNameMaxLength));
      expect(taken, isNot(contains(name)));
    });
  });

  test('a blank source name still yields something valid to send', () {
    // min(1) — an empty name is a 400, so never propose one.
    expect(suggestedCloneName('   ', const []), isNotEmpty);
    expect(suggestedCloneName('   ', const []), 'Template (Copy)');
  });
}
