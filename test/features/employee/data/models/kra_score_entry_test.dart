import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/data/models/enums.dart';
import 'package:vistar_app/features/employee/data/models/kra_score_entry.dart';

void main() {
  group('KraScoreEntry.isFilled', () {
    test('is true when selfRating is set', () {
      final e = _entry(selfRating: 8.0);
      expect(e.isFilled, isTrue);
    });

    test('is true when isNotApplicable even with null rating', () {
      final e = _entry(selfRating: null, isNotApplicable: true);
      expect(e.isFilled, isTrue);
    });

    test('is false when selfRating is null and not N/A', () {
      final e = _entry(selfRating: null);
      expect(e.isFilled, isFalse);
    });
  });

  group('KraScoreEntry.weightedContribution', () {
    test('computes correctly for a normal score', () {
      // weight 0.4 → weightagePercent 40, score 8/10 → normalised 0.8
      // contribution = 0.8 * 40 = 32
      final e = _entry(weight: 0.4, maxScore: 10, selfRating: 8.0);
      expect(e.weightedContribution, closeTo(32.0, 0.001));
    });

    test('returns 0 when score is null', () {
      final e = _entry(weight: 0.4, maxScore: 10, selfRating: null);
      expect(e.weightedContribution, 0);
    });

    test('returns 0 when isNotApplicable', () {
      final e = _entry(
        weight: 0.4,
        maxScore: 10,
        selfRating: 9.0,
        isNotApplicable: true,
      );
      expect(e.weightedContribution, 0);
    });

    test('handles weightage > 1 (percent form)', () {
      // weight 40 → weightagePercent 40, score 5/10 → normalised 0.5
      // contribution = 0.5 * 40 = 20
      final e = _entry(weight: 40, maxScore: 10, selfRating: 5.0);
      expect(e.weightedContribution, closeTo(20.0, 0.001));
    });

    test('handles maxScore of 5 correctly', () {
      // weight 0.2 → weightagePercent 20, score 3/5 → normalised 0.6
      // contribution = 0.6 * 20 = 12
      final e = _entry(weight: 0.2, maxScore: 5, selfRating: 3.0);
      expect(e.weightedContribution, closeTo(12.0, 0.001));
    });

    test('handles zero maxScore without NaN', () {
      final e = _entry(weight: 0.2, maxScore: 0, selfRating: 5.0);
      expect(e.weightedContribution, 0);
    });
  });

  group('KraScoreEntry.weightagePercent', () {
    test('converts fraction to percent (0.05 → 5)', () {
      final e = _entry(weight: 0.05);
      expect(e.weightagePercent, closeTo(5.0, 0.001));
    });

    test('leaves percent-form alone (40 → 40)', () {
      final e = _entry(weight: 40);
      expect(e.weightagePercent, 40);
    });
  });

  group('KraScoreEntry JSON round-trip (draft storage)', () {
    test('toJson → fromJson preserves all fields', () {
      final original = _entry(
        selfRating: 7.5,
        selfRemark: 'did the thing',
        isNotApplicable: false,
        weight: 0.3,
        maxScore: 10,
      );
      final restored = KraScoreEntry.fromJson(original.toJson());
      expect(restored.monthlyScoreId, original.monthlyScoreId);
      expect(restored.selfRating, original.selfRating);
      expect(restored.selfRemark, original.selfRemark);
      expect(restored.weight, original.weight);
      expect(restored.maxScore, original.maxScore);
      expect(restored.isNotApplicable, original.isNotApplicable);
    });

    test('fromJson handles null selfRating correctly', () {
      final original = _entry(selfRating: null);
      final restored = KraScoreEntry.fromJson(original.toJson());
      expect(restored.selfRating, isNull);
      expect(restored.isFilled, isFalse);
    });
  });

  group('KraScoreEntry attachment (local proof)', () {
    test('hasAttachment reflects whether a file name is set', () {
      expect(_entry().hasAttachment, isFalse);
      expect(
        _entry()
            .copyWith(attachmentName: 'proof.pdf', attachmentPath: '/x')
            .hasAttachment,
        isTrue,
      );
    });

    test('attachment round-trips through draft JSON', () {
      final original = _entry(selfRating: 6.0).copyWith(
        attachmentName: 'evidence.png',
        attachmentPath: '/tmp/evidence.png',
      );
      final restored = KraScoreEntry.fromJson(original.toJson());
      expect(restored.attachmentName, 'evidence.png');
      expect(restored.attachmentPath, '/tmp/evidence.png');
      expect(restored.hasAttachment, isTrue);
    });

    test('copyWith can clear the attachment back to null', () {
      final withFile = _entry().copyWith(
        attachmentName: 'a.jpg',
        attachmentPath: '/a.jpg',
      );
      final cleared =
          withFile.copyWith(attachmentName: null, attachmentPath: null);
      expect(cleared.hasAttachment, isFalse);
      expect(cleared.attachmentPath, isNull);
    });

    test('copyWith preserves the attachment when untouched', () {
      final withFile = _entry().copyWith(
        attachmentName: 'a.jpg',
        attachmentPath: '/a.jpg',
      );
      expect(withFile.copyWith(selfRemark: 'x').attachmentName, 'a.jpg');
    });
  });
}

KraScoreEntry _entry({
  double weight = 0.1,
  double maxScore = 10,
  double? selfRating,
  String selfRemark = '',
  bool isNotApplicable = false,
}) {
  return KraScoreEntry(
    monthlyScoreId: 'test-cell-1',
    reviewRowId: 'test-row-1',
    monthId: 'test-month-1',
    itemName: 'Test KRA',
    weight: weight,
    maxScore: maxScore,
    scoreSource: ScoreSource.self,
    displayOrder: 0,
    monthLabel: 'May 2026',
    monthStatus: ReviewMonthStatus.open,
    selfRating: selfRating,
    selfRemark: selfRemark,
    isNotApplicable: isNotApplicable,
  );
}
