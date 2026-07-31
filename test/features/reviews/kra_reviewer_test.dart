import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

void main() {
  group('KraReviewer.fromApi', () {
    test('maps canonical wire forms', () {
      expect(KraReviewer.fromApi('REPORTING_MANAGER'),
          KraReviewer.reportingManager);
      expect(KraReviewer.fromApi('HR'), KraReviewer.hr);
      expect(KraReviewer.fromApi('ACCOUNTS'), KraReviewer.accounts);
    });

    test('tolerates score_source vocabulary + case/spacing', () {
      expect(KraReviewer.fromApi('  manager '), KraReviewer.reportingManager);
      expect(KraReviewer.fromApi('HR_FEED'), KraReviewer.hr);
      expect(KraReviewer.fromApi('accounts_feed'), KraReviewer.accounts);
      expect(KraReviewer.fromApi('FINANCE'), KraReviewer.accounts);
    });

    test('blank / unknown → null (unassigned)', () {
      expect(KraReviewer.fromApi(null), isNull);
      expect(KraReviewer.fromApi(''), isNull);
      expect(KraReviewer.fromApi('CFO'), isNull);
    });

    test('round-trips through toApiString', () {
      for (final r in KraReviewer.values) {
        expect(KraReviewer.fromApi(r.toApiString()), r);
      }
    });

    test('round-trips through toScoreSource (backend enum vocabulary)', () {
      expect(KraReviewer.reportingManager.toScoreSource(), 'MANAGER');
      expect(KraReviewer.hr.toScoreSource(), 'HR_FEED');
      expect(KraReviewer.accounts.toScoreSource(), 'ACCOUNTS_FEED');
      for (final r in KraReviewer.values) {
        expect(KraReviewer.fromApi(r.toScoreSource()), r);
      }
    });
  });

  group('MonthlyKraRow.reviewStage', () {
    test('maps each reviewer to its Review-cycle stage', () {
      expect(
          const MonthlyKraRow(
                  id: 'a',
                  name: 'A',
                  weightagePercent: 100,
                  reviewerGroup: KraReviewer.reportingManager)
              .reviewStage,
          ReviewStage.reportingManagerRating);
      expect(
          const MonthlyKraRow(
                  id: 'a',
                  name: 'A',
                  weightagePercent: 100,
                  reviewerGroup: KraReviewer.hr)
              .reviewStage,
          ReviewStage.accountHrRating);
      expect(
          const MonthlyKraRow(
                  id: 'a',
                  name: 'A',
                  weightagePercent: 100,
                  reviewerGroup: KraReviewer.accounts)
              .reviewStage,
          ReviewStage.financeRating);
    });

    test('null reviewer → null stage (legacy row)', () {
      expect(
          const MonthlyKraRow(id: 'a', name: 'A', weightagePercent: 100)
              .reviewStage,
          isNull);
    });
  });

  group('MonthlyKraRow JSON', () {
    test('reads reviewerGroup from any of the tolerated keys', () {
      expect(
          MonthlyKraRow.fromJson(
                  {'id': 'a', 'name': 'A', 'reviewerGroup': 'HR'})
              .reviewerGroup,
          KraReviewer.hr);
      expect(
          MonthlyKraRow.fromJson(
                  {'id': 'a', 'name': 'A', 'reviewer_group': 'ACCOUNTS'})
              .reviewerGroup,
          KraReviewer.accounts);
      expect(
          MonthlyKraRow.fromJson(
                  {'id': 'a', 'name': 'A', 'scoreSource': 'MANAGER'})
              .reviewerGroup,
          KraReviewer.reportingManager);
    });

    test('emits reviewerGroup only when assigned', () {
      expect(
          const MonthlyKraRow(
                  id: 'a',
                  name: 'A',
                  weightagePercent: 100,
                  reviewerGroup: KraReviewer.accounts)
              .toJson()['reviewerGroup'],
          'ACCOUNTS');
      expect(
          const MonthlyKraRow(id: 'a', name: 'A', weightagePercent: 100)
              .toJson()
              .containsKey('reviewerGroup'),
          isFalse);
    });
  });
}
