import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/manager/data/models/review_permissions.dart';

void main() {
  group('ReviewPermissions.isUrgent', () {
    test('true when deadline is within 3 days', () {
      expect(_p(deadline: 3).isUrgent, isTrue);
      expect(_p(deadline: 0).isUrgent, isTrue);
      expect(_p(deadline: 1).isUrgent, isTrue);
    });

    test('false beyond 3 days', () {
      expect(_p(deadline: 4).isUrgent, isFalse);
      expect(_p(deadline: 10).isUrgent, isFalse);
    });

    test('false when deadline is null (no deadline set)', () {
      expect(_p(deadline: null).isUrgent, isFalse);
    });

    test('false when overdue (handled separately by isOverdue)', () {
      expect(_p(deadline: -1).isUrgent, isFalse);
    });
  });

  group('ReviewPermissions.isOverdue', () {
    test('true for negative days', () {
      expect(_p(deadline: -1).isOverdue, isTrue);
      expect(_p(deadline: -100).isOverdue, isTrue);
    });

    test('false for zero or positive days', () {
      expect(_p(deadline: 0).isOverdue, isFalse);
      expect(_p(deadline: 5).isOverdue, isFalse);
    });

    test('false when deadline is null', () {
      expect(_p(deadline: null).isOverdue, isFalse);
    });
  });

  group('ReviewPermissions JSON', () {
    test('round-trips through fromJson/toJson', () {
      const original = ReviewPermissions(
        canRate: true,
        canEdit: false,
        deadlineRemaining: 5,
      );
      final json = original.toJson();
      final restored = ReviewPermissions.fromJson(json);
      expect(restored.canRate, isTrue);
      expect(restored.canEdit, isFalse);
      expect(restored.deadlineRemaining, 5);
    });

    test('tolerates missing fields with safe defaults', () {
      final p = ReviewPermissions.fromJson(const {});
      expect(p.canRate, isFalse);
      expect(p.canEdit, isFalse);
      expect(p.deadlineRemaining, isNull);
    });
  });

  group('ReviewPermissions.copyWith', () {
    test('preserves untouched fields', () {
      const p = ReviewPermissions(
        canRate: true,
        canEdit: true,
        deadlineRemaining: 3,
      );
      final c = p.copyWith(canRate: false);
      expect(c.canRate, isFalse);
      expect(c.canEdit, isTrue);
      expect(c.deadlineRemaining, 3);
    });

    test('can clear deadlineRemaining via explicit null', () {
      const p = ReviewPermissions(
        canRate: true,
        canEdit: false,
        deadlineRemaining: 5,
      );
      final c = p.copyWith(deadlineRemaining: null);
      expect(c.deadlineRemaining, isNull);
    });
  });
}

ReviewPermissions _p({int? deadline}) => ReviewPermissions(
      canRate: true,
      canEdit: false,
      deadlineRemaining: deadline,
    );
