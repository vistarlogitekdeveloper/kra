import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/models/kra_template.dart';

/// Guards the KRA Templates list-card metrics. The list endpoint returns
/// the item count under `_count.items` but omits the `items` array, so the
/// count must come from `_count` (it was previously derived from
/// `items.length`, which is empty on the list → the cards showed
/// "0 KRAs / 0%" even for templates that had items). The weightage total
/// is only known once items are hydrated from the detail endpoint.
void main() {
  group('KraTemplate list payload (with _count, no items)', () {
    final listJson = {
      'id': 'tpl_bd_manager',
      'name': 'BD Manager KRA',
      'role': 'BD_MANAGER',
      'description': 'desc',
      'isActive': true,
      '_count': {'items': 4, 'defaultEmployees': 1, 'reviews': 0},
    };

    test('item count is read from _count.items', () {
      final t = KraTemplate.fromJson(listJson);
      expect(t.items, isEmpty);
      expect(t.itemCount, 4);
      expect(t.displayItemCount, 4);
    });

    test('weightage data is absent until items are hydrated', () {
      final t = KraTemplate.fromJson(listJson);
      expect(t.hasWeightageData, isFalse);
      expect(t.totalWeightage, 0);
    });
  });

  group('KraTemplate detail payload (with items, no _count)', () {
    final detailJson = {
      'id': 'tpl_bd_manager',
      'name': 'BD Manager KRA',
      'role': 'BD_MANAGER',
      'isActive': true,
      'items': [
        {'id': 'i1', 'name': 'Revenue', 'weightage': '0.4', 'sortOrder': 1},
        {'id': 'i2', 'name': 'Ops', 'weightage': '0.3', 'sortOrder': 2},
        {'id': 'i3', 'name': 'Budget', 'weightage': '0.3', 'sortOrder': 3},
      ],
    };

    test('count comes from the loaded items', () {
      final t = KraTemplate.fromJson(detailJson);
      expect(t.items, hasLength(3));
      expect(t.displayItemCount, 3);
    });

    test('weightage totals to 100% and validates as balanced', () {
      final t = KraTemplate.fromJson(detailJson);
      expect(t.hasWeightageData, isTrue);
      expect(t.totalWeightage, closeTo(100, 0.001));
      expect(t.hasValidWeightage, isTrue);
    });
  });
}
