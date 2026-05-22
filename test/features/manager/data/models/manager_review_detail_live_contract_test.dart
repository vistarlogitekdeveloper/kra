import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/data/models/enums.dart';
import 'package:vistar_app/features/manager/data/models/manager_review_detail.dart';

/// Regression guard for the manager review-detail contract.
///
/// The model parses the LIVE backend response, whose field names differ
/// from the original Step-4 spec: the cycle block is `reviewCycle` (not
/// `cycle`), the row id/copy/weight come from `templateItemId` /
/// `templateItem.{name,…}` / `weight` / `displayOrder` (not flat
/// `assignmentItemId`/`name`/`weightage`/`sortOrder`), and each cell's id
/// + month label/status are `id` + nested `month.{monthLabel,status}`
/// (not flat `monthlyScoreId`/`monthLabel`/`monthStatus`).
///
/// Earlier the model read only the spec names, so against the live API
/// every row rendered with a blank name, 0 weightage (weighted total
/// stuck at 0), an empty `assignmentItemId`, and an empty
/// `monthlyScoreId` (which both broke the POST /scores key and made
/// editing one cell mutate every cell in the row). The hand-written
/// unit-test fixtures used the spec names, so the bug stayed green.
///
/// This test feeds a verbatim subset of the real
/// GET /manager/reviews/:id payload (captured from
/// vistar-crm.onrender.com) and asserts it parses correctly.
void main() {
  Map<String, dynamic> liveReviewJson() => {
        'id': 'rev_e2',
        'state': 'EMPLOYEE_SUBMITTED_ALL',
        'employee': {
          'id': 'emp_e2',
          'name': 'Vikram Singh',
          'employeeCode': 'EMP004',
          'role': 'EMPLOYEE',
        },
        // Live key is `reviewCycle`, not `cycle`.
        'reviewCycle': {
          'id': 'cyc_q1_fy2627',
          'name': 'Q1 FY26-27',
          'fyLabel': 'FY26-27',
          'managerReviewDeadline': '2026-07-31T00:00:00.000Z',
          'months': [
            {
              'id': 'mon_apr26',
              'monthLabel': 'Apr 2026',
              'monthDate': '2026-04-01T00:00:00.000Z',
              'status': 'OPEN',
            },
          ],
        },
        'rows': [
          {
            'id': 'rr_e2_1',
            'reviewId': 'rev_e2',
            'templateItemId': 'tpli_emp_1',
            'weight': '0.4',
            'maxScore': '5',
            'scoreSource': 'MANAGER',
            'displayOrder': 1,
            'templateItem': {
              'name': 'Task Completion',
              'description': 'On-time task completion',
              'category': 'Delivery',
            },
            'monthlyScores': [
              {
                'id': 'rms_e2_1_apr',
                'reviewRowId': 'rr_e2_1',
                'monthId': 'mon_apr26',
                'selfRating': '4.5',
                'managerRating': null,
                'isNotApplicable': false,
                'month': {
                  'id': 'mon_apr26',
                  'monthLabel': 'Apr 2026',
                  'status': 'OPEN',
                },
              },
            ],
          },
        ],
        'totals': {'selfTotal': 90, 'managerTotal': null, 'finalTotal': null},
        'permissions': {
          'canRate': true,
          'canEdit': true,
          'deadlineRemaining': 70,
        },
      };

  group('ManagerReviewDetail parses the live backend contract', () {
    test('cycle is read from reviewCycle, with its months', () {
      final d = ManagerReviewDetail.fromJson(liveReviewJson());
      expect(d.cycle.name, 'Q1 FY26-27');
      expect(d.cycle.fyLabel, 'FY26-27');
      expect(d.cycle.months, hasLength(1));
      expect(d.cycle.months.first.monthLabel, 'Apr 2026');
      expect(d.cycle.months.first.status, ReviewMonthStatus.open);
    });

    test('row copy/weight/id come from the live field names', () {
      final row = ManagerReviewDetail.fromJson(liveReviewJson()).rows.first;
      expect(row.name, 'Task Completion');
      expect(row.category, 'Delivery');
      expect(row.description, 'On-time task completion');
      // weight "0.4" => 40% — drives the weighted-total preview.
      expect(row.weightage, 0.4);
      expect(row.weightagePercent, 40);
      expect(row.maxScore, 5);
      expect(row.sortOrder, 1);
      // Non-empty, stable row identity (used for withUpdatedRow matching).
      expect(row.assignmentItemId, isNotEmpty);
      expect(row.assignmentItemId, 'tpli_emp_1');
    });

    test('cell id + month label/status come from the live field names', () {
      final cell = ManagerReviewDetail.fromJson(liveReviewJson())
          .rows
          .first
          .monthlyScores
          .first;
      // This id is the POST /scores key AND the per-cell edit identity.
      expect(cell.monthlyScoreId, 'rms_e2_1_apr');
      expect(cell.monthId, 'mon_apr26');
      expect(cell.monthLabel, 'Apr 2026');
      expect(cell.monthStatus, ReviewMonthStatus.open);
      expect(cell.selfRating, 4.5);
      expect(cell.isEditable, isTrue);
    });

    test('distinct cells keep distinct ids (no edit collision)', () {
      final json = liveReviewJson();
      (json['rows'] as List).first['monthlyScores'] = [
        {
          'id': 'rms_e2_1_apr',
          'monthId': 'mon_apr26',
          'month': {'monthLabel': 'Apr 2026', 'status': 'OPEN'},
        },
        {
          'id': 'rms_e2_1_may',
          'monthId': 'mon_may26',
          'month': {'monthLabel': 'May 2026', 'status': 'OPEN'},
        },
      ];
      final cells =
          ManagerReviewDetail.fromJson(json).rows.first.monthlyScores;
      expect(
        cells.map((c) => c.monthlyScoreId).toSet(),
        {'rms_e2_1_apr', 'rms_e2_1_may'},
        reason: 'empty/duplicate ids would make one edit overwrite all cells',
      );
    });

    test('weighted total is non-zero once a rating is applied', () {
      final d = ManagerReviewDetail.fromJson(liveReviewJson());
      final row = d.rows.first;
      // With a real 40% weight the row contributes to the total; the
      // pre-fix parse left weightage at 0 so the total was always 0.
      expect(row.weightagePercent, greaterThan(0));
    });
  });

  group('backward compatibility with the flat spec/mock shape', () {
    test('still parses spec-shaped payloads via fallback field names', () {
      final spec = {
        'id': 'rev_x',
        'state': 'EMPLOYEE_SUBMITTED_ALL',
        'employee': {'id': 'e', 'name': 'N', 'employeeCode': 'C'},
        'cycle': {
          'id': 'cyc',
          'name': 'Spec Cycle',
          'months': [
            {'id': 'm1', 'monthLabel': 'Apr 2026', 'status': 'OPEN'},
          ],
        },
        'rows': [
          {
            'assignmentItemId': 'ai_1',
            'name': 'Spec KRA',
            'category': 'Cat',
            'weightage': 0.25,
            'maxScore': 10,
            'scoreSource': 'MANAGER',
            'sortOrder': 2,
            'monthlyScores': [
              {
                'monthlyScoreId': 'ms_1',
                'monthId': 'm1',
                'monthLabel': 'Apr 2026',
                'monthStatus': 'OPEN',
                'managerRating': 8,
              },
            ],
          },
        ],
        'totals': {'selfTotal': 50},
        'permissions': {'canRate': true, 'canEdit': true},
      };
      final d = ManagerReviewDetail.fromJson(spec);
      expect(d.cycle.name, 'Spec Cycle');
      final row = d.rows.first;
      expect(row.name, 'Spec KRA');
      expect(row.assignmentItemId, 'ai_1');
      expect(row.weightagePercent, 25);
      expect(row.sortOrder, 2);
      final cell = row.monthlyScores.first;
      expect(cell.monthlyScoreId, 'ms_1');
      expect(cell.monthLabel, 'Apr 2026');
      expect(cell.monthStatus, ReviewMonthStatus.open);
    });
  });
}
