import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
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

    test(
        'toJson coerces null description / target / trackingMethod to empty '
        'strings (backend Zod rejects nulls on POST + PATCH)', () {
      const item = KraTemplateItem(
        name: 'Revenue',
        weightage: 50,
        sortOrder: 0,
      );

      final json = item.toJson();

      expect(json['description'], '');
      expect(json['target'], '');
      expect(json['trackingMethod'], '');
    });

    test('toJson preserves non-null strings verbatim', () {
      const item = KraTemplateItem(
        name: 'Revenue',
        description: 'Top-line growth',
        target: '10 cr',
        trackingMethod: 'CRM dashboard',
        weightage: 50,
        sortOrder: 0,
      );

      final json = item.toJson();

      expect(json['description'], 'Top-line growth');
      expect(json['target'], '10 cr');
      expect(json['trackingMethod'], 'CRM dashboard');
    });

    test(
        'weightagePercent does NOT inflate sub-1 values — a user-typed 1 (1%) '
        'stays 1, not 100 (regression: the old <=1.0 heuristic mangled it)',
        () {
      const onePercent = KraTemplateItem(name: 'Tiny', weightage: 1, sortOrder: 0);
      expect(onePercent.weightagePercent, 1);
      expect(onePercent.toJson()['weightage'], closeTo(0.01, 1e-9));

      const halfPercent =
          KraTemplateItem(name: 'Tinier', weightage: 0.5, sortOrder: 0);
      expect(halfPercent.weightagePercent, 0.5);
      expect(halfPercent.toJson()['weightage'], closeTo(0.005, 1e-9));
    });

    test('fromJson normalises a sub-1% wire fraction without double-scaling', () {
      // "0.005" on the wire is 0.5%, which must read back as 0.5 — not 50.
      final item = KraTemplateItem.fromJson({
        'name': 'Half percent',
        'weightage': '0.005',
        'sortOrder': 1,
      });
      expect(item.weightagePercent, closeTo(0.5, 1e-9));
    });

    test('toJson sends scoreSource in the backend enum vocabulary', () {
      // The live template API validates scoreSource against
      // MANAGER/HR_FEED/OPS_FEED/ACCOUNTS_FEED and rejects anything else, so
      // Accounts MUST serialize as ACCOUNTS_FEED (not "ACCOUNTS") to persist.
      const item = KraTemplateItem(
        name: 'Collections',
        weightage: 40,
        sortOrder: 0,
        reviewerGroup: KraReviewer.accounts,
      );
      final json = item.toJson();
      expect(json['scoreSource'], 'ACCOUNTS_FEED');
      expect(json['reviewerGroup'], 'ACCOUNTS');
    });

    test('each reviewer maps to its ScoreSourceEnum value', () {
      String src(KraReviewer r) =>
          KraTemplateItem(name: 'x', weightage: 1, sortOrder: 0, reviewerGroup: r)
              .toJson()['scoreSource'] as String;
      expect(src(KraReviewer.reportingManager), 'MANAGER');
      expect(src(KraReviewer.hr), 'HR_FEED');
      expect(src(KraReviewer.accounts), 'ACCOUNTS_FEED');
    });

    test('toJson omits the reviewer keys when unassigned', () {
      const item = KraTemplateItem(name: 'Unassigned', weightage: 10, sortOrder: 0);
      final json = item.toJson();
      expect(json.containsKey('reviewerGroup'), isFalse);
      expect(json.containsKey('scoreSource'), isFalse);
    });

    test('fromJson reads the reviewer from reviewerGroup / score_source', () {
      expect(
          KraTemplateItem.fromJson(
                  {'name': 'A', 'weightage': '0.4', 'reviewerGroup': 'HR'})
              .reviewerGroup,
          KraReviewer.hr);
      // A raw-SQL backend may surface the score_source column instead.
      expect(
          KraTemplateItem.fromJson(
                  {'name': 'A', 'weightage': '0.4', 'score_source': 'MANAGER'})
              .reviewerGroup,
          KraReviewer.reportingManager);
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
