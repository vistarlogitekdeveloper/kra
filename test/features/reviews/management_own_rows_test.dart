import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Under administrators-only, management rates the LEFTOVER KRAs — it does not
/// get authority over HR's and Accounts' own scores.
///
/// Reported from the live sheet: management opened an employee with three KRAs
/// (one HR, one Accounts, one management) and had an editable pencil in the
/// Mgmt column of all three, so it could overwrite the HR and Accounts numbers.
/// The Review column was already correctly locked; the Mgmt column was not,
/// because its gate was per-REVIEW (`canEditManagement`) with nothing per-ROW.
///
/// The distinction the two flows draw on that column:
///   standard   — management holds no Review seat, so Mgmt is an OVERRIDE over
///                every row, and must stay that way.
///   adminOnly  — management is a RATER of its own rows only.
void main() {
  MonthlyKraRow row(KraReviewer? assigned) => MonthlyKraRow(
        id: 'k-${assigned?.name ?? 'none'}',
        name: 'KRA ${assigned?.name ?? 'unassigned'}',
        weightagePercent: 100,
        maxScore: 10,
        reviewerGroup: assigned,
      );

  group('administrators-only: management scores only its own rows', () {
    test('the management-assigned KRA is open — that is its seat', () {
      expect(
        managementMayScoreRow(
            row(KraReviewer.reportingManager), ReviewFlow.adminOnly),
        isTrue,
      );
    });

    test('an UNASSIGNED KRA is open too — the remainder includes it', () {
      // Matches defaultReviewerFor(adminOnly): a KRA nobody was given belongs
      // to management, so its Mgmt cell must be usable.
      expect(managementMayScoreRow(row(null), ReviewFlow.adminOnly), isTrue);
    });

    test('the HR-assigned KRA is CLOSED — the reported defect', () {
      expect(
        managementMayScoreRow(row(KraReviewer.hr), ReviewFlow.adminOnly),
        isFalse,
        reason: 'only HR scores the HR KRA',
      );
    });

    test('the Accounts-assigned KRA is CLOSED — the reported defect', () {
      expect(
        managementMayScoreRow(row(KraReviewer.accounts), ReviewFlow.adminOnly),
        isFalse,
        reason: 'only Accounts scores the Accounts KRA',
      );
    });

    test('exactly one of the three seats is management\'s', () {
      final open = KraReviewer.values
          .where((r) => managementMayScoreRow(row(r), ReviewFlow.adminOnly))
          .toList();
      expect(open, [KraReviewer.reportingManager],
          reason: 'the remainder seat, and nothing else');
    });
  });

  group('standard: the override column is UNCHANGED', () {
    test('every seat stays open to management', () {
      // Management holds no Review seat on the standard pipeline, so the Mgmt
      // column is the sign-off's per-KRA override on rework. Narrowing it here
      // would remove the only way to correct a score, in the flow that is in
      // production.
      for (final assigned in [...KraReviewer.values, null]) {
        expect(
          managementMayScoreRow(row(assigned), ReviewFlow.standard),
          isTrue,
          reason: 'assigned=${assigned?.name ?? 'none'}',
        );
      }
    });
  });

  group('the rule is derived, not restated', () {
    test('it keys on whether the manager seat is relationship-gated', () {
      // The same predicate that decides who holds the remainder seat decides
      // whether the Mgmt column is a seat or an override. Restating "flow ==
      // adminOnly" here is how the two would drift.
      for (final flow in ReviewFlow.values) {
        final relationship =
            stageIsRelationshipGated(ReviewStage.reportingManagerRating, flow);
        expect(
          managementMayScoreRow(row(KraReviewer.hr), flow),
          relationship,
          reason: 'flow=${flow.name}: an HR row is open to management only '
              'where management has no Review seat of its own',
        );
      }
    });
  });
}
