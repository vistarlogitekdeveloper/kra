import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/models/kra_template_item.dart';

/// Pins the wire contract for KRA template items, in particular the
/// 1-based `sortOrder` translation.
///
/// The live backend enforces `sortOrder >= 1` via Zod on POST /kra-templates,
/// so a 0-based payload comes back as `VAL_001 "Too small: expected number
/// to be >=1"`. We keep `sortOrder` 0-based internally (it lines up with
/// `_items[i]` in the form) and offset by +1 at the wire boundary.
void main() {
  group('KraTemplateItem wire contract', () {
    test('toJson sends 1-based sortOrder even though the model is 0-based', () {
      const item = KraTemplateItem(
        name: 'Revenue',
        weightage: 40,
        sortOrder: 0,
      );

      final json = item.toJson();

      expect(json['sortOrder'], 1, reason: 'wire form must be 1-based');
    });

    test('toJson sends weightage as a 0–1 fraction', () {
      const item = KraTemplateItem(name: 'Ops', weightage: 60, sortOrder: 1);

      final json = item.toJson();

      expect(json['weightage'], closeTo(0.6, 1e-9));
      expect(json['sortOrder'], 2);
    });

    test('fromJson normalises 1-based wire sortOrder back to 0-based internal',
        () {
      final item = KraTemplateItem.fromJson({
        'id': 'i1',
        'name': 'Revenue',
        'weightage': '0.4',
        'sortOrder': 1,
      });

      expect(item.sortOrder, 0);
      expect(item.weightagePercent, closeTo(40, 1e-9));
    });

    test('fromJson clamps a malformed 0 sortOrder to 0 (does not go negative)',
        () {
      final item = KraTemplateItem.fromJson({
        'name': 'Legacy',
        'weightage': '0.5',
        'sortOrder': 0,
      });

      expect(item.sortOrder, 0);
    });

    test('round trip: internal 0,1,2 → wire 1,2,3 → internal 0,1,2', () {
      const items = [
        KraTemplateItem(name: 'A', weightage: 40, sortOrder: 0),
        KraTemplateItem(name: 'B', weightage: 30, sortOrder: 1),
        KraTemplateItem(name: 'C', weightage: 30, sortOrder: 2),
      ];

      final wire = items.map((e) => e.toJson()).toList();
      expect(wire.map((j) => j['sortOrder']).toList(), [1, 2, 3]);

      final readBack = wire.map(KraTemplateItem.fromJson).toList();
      expect(readBack.map((i) => i.sortOrder).toList(), [0, 1, 2]);
    });
  });
}
