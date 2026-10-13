import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/stage_status.dart';
import 'package:vistar_app/features/reviews/data/repositories/mock_monthly_review_repository.dart';
import 'package:vistar_app/features/reviews/presentation/providers/monthly_review_providers.dart';

/// The identity line under the employee's name on the quarterly KRA sheet:
/// code · grade · reporting manager · location.
///
/// Reported as "the reporting manager comes as superadmin", and the label was
/// half the problem: `Mgr: Super Admin` reads as an app quirk, so a value that
/// was simply WRONG IN THE DATA looked like a rendering bug and went
/// unquestioned for a quarter. A label that names the field it reports sends
/// the reader to HR → Employee → Reporting Manager instead.
///
/// The second rule here is about absence. Null on this line means "the payload
/// did not carry it", which is a different claim from "the employee has none".
/// Printing "Not assigned" for the first would send someone to fix a field that
/// is already set — so a null part is DROPPED, and the one exception
/// (`managerUnassigned`) is passed only by a caller that can tell the
/// difference, i.e. that can also see `managerId` is null.
void main() {
  group('the line spells its labels out', () {
    test('the manager is named as the reporting manager, not "Mgr"', () {
      final line = AppStrings.sheetEmployeeMeta(
        employeeCode: 'VLPL0123',
        grade: 'M1',
        managerName: 'Super Admin',
      );

      expect(line, contains('Reporting Manager: Super Admin'));
      // The abbreviation is what made a data problem look like a UI one.
      expect(line, isNot(contains('Mgr')));
    });

    test('the location is labelled, so it is not read as another code', () {
      final line = AppStrings.sheetEmployeeMeta(
        employeeCode: 'VLPL0123',
        projectLocation: 'Bhiwandi',
      );

      expect(line, contains('Location: Bhiwandi'));
    });

    test('every part appears, in reading order', () {
      final line = AppStrings.sheetEmployeeMeta(
        employeeCode: 'VLPL0123',
        grade: 'M1',
        managerName: 'Amol Veer',
        projectLocation: 'Adept, Pune',
      );

      expect(
        line,
        'VLPL0123  ·  Grade M1  ·  Reporting Manager: Amol Veer  ·  '
        'Location: Adept, Pune',
      );
    });
  });

  group('absent is not the same as unassigned', () {
    test('an unknown location is dropped, never printed as a placeholder', () {
      // The review-detail payload carries no location at all on a backend
      // that has not been patched. Claiming "not assigned" there states
      // something this screen cannot know.
      final line = AppStrings.sheetEmployeeMeta(
        employeeCode: 'VLPL0123',
        projectLocation: null,
      );

      expect(line, 'VLPL0123');
      expect(line, isNot(contains('Location')));
    });

    test('an unknown manager is dropped too, by default', () {
      final line = AppStrings.sheetEmployeeMeta(
        employeeCode: 'VLPL0123',
        managerName: null,
      );

      expect(line, isNot(contains('Reporting Manager')));
    });

    test('a manager known to be absent IS stated', () {
      // No name AND no id — the one case the caller can distinguish. Silence
      // here hides the very gap the reader is auditing.
      final line = AppStrings.sheetEmployeeMeta(
        employeeCode: 'VLPL0123',
        managerName: null,
        managerUnassigned: true,
      );

      expect(line, contains('Reporting Manager: Not assigned'));
    });

    test('a real name beats the unassigned flag', () {
      final line = AppStrings.sheetEmployeeMeta(
        managerName: 'Super Admin',
        managerUnassigned: true,
      );

      expect(line, 'Reporting Manager: Super Admin');
    });

    test('blank strings count as absent, not as an empty label', () {
      // The backend sends '' for a cleared column often enough that a trim
      // check is the difference between a clean line and "Grade   ·  ".
      final line = AppStrings.sheetEmployeeMeta(
        employeeCode: '  ',
        grade: '',
        managerName: '   ',
        projectLocation: '',
      );

      expect(line, isEmpty);
    });
  });

  group('MonthlyReview carries the location', () {
    Map<String, dynamic> base() => {
          'id': 'r1',
          'employeeId': 'e1',
          'employeeName': 'Amol Laxman Veer',
          'employeeCode': 'VLPL0123',
          'period': '2026-07',
        };

    test('a flat string reads directly', () {
      final r = MonthlyReview.fromJson(base()..['projectLocation'] = 'HO');
      expect(r.projectLocation, 'HO');
    });

    test('an object yields its NAME, never the stringified map', () {
      // `JsonParse.parseString` falls back to `toString()`, so an unguarded
      // read puts a literal "{id: loc_ho, name: HO}" on the header — valid
      // output that no exception catches. Same trap as MonthlyReviewSummary.
      final r = MonthlyReview.fromJson(
        base()..['projectLocation'] = {'id': 'loc_ho', 'name': 'HO'},
      );

      expect(r.projectLocation, 'HO');
      expect(r.projectLocation, isNot(contains('{')));
    });

    test('a payload without the key is null, not empty', () {
      expect(MonthlyReview.fromJson(base()).projectLocation, isNull);
    });

    test('copyWith carries it', () {
      // The sheet copyWiths every review on load (_applyReviewerMap). Dropping
      // the location there would erase exactly what the provider backfilled —
      // the same shape of bug as the monthDate one in the manager matrix.
      final r = MonthlyReview.fromJson(base()..['projectLocation'] = 'HO');
      expect(r.copyWith(grade: 'M1').projectLocation, 'HO');
    });
  });

  group('the sheet backfills the location the detail payload omits', () {
    const scope = ReviewScope(
      userId: 'hr1',
      userName: 'HR Admin',
      role: UserRole.hrAdmin,
    );

    Future<MonthlyReview?> firstReview(_SheetRepo repo) async {
      final container = ProviderContainer(overrides: [
        currentReviewScopeProvider.overrideWithValue(scope),
        monthlyReviewRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      final sheet = await container.read(
        quarterlySheetProvider(
          (employeeId: 'e1', anchor: const ReviewPeriod(2026, 8)),
        ).future,
      );
      return sheet.reviews.firstWhere((r) => r != null, orElse: () => null);
    }

    test('the list row supplies what the detail does not', () async {
      // `findHeader` joins no project_locations, so GET /reviews/monthly/:id
      // never carries one — while the list row for that same review does. The
      // provider already holds both; without the carry-across the header could
      // not show a location at all.
      final review = await firstReview(
        _SheetRepo(summaryLocation: 'Bhiwandi'),
      );

      expect(review?.projectLocation, 'Bhiwandi');
    });

    test('a detail that DOES carry one wins', () async {
      // So the day the backend adds the join, the authoritative payload is
      // used rather than being overwritten by the list projection.
      final review = await firstReview(
        _SheetRepo(summaryLocation: 'Bhiwandi', detailLocation: 'HO'),
      );

      expect(review?.projectLocation, 'HO');
    });

    test('neither knowing leaves it null, not blank', () async {
      // Null is what makes the header DROP the field rather than assert
      // "Not assigned" about a location it never saw.
      final review = await firstReview(_SheetRepo());

      expect(review?.projectLocation, isNull);
    });
  });
}

/// Serves one review for `e1`, with the location present on the list row, the
/// detail row, both or neither.
class _SheetRepo extends MockMonthlyReviewRepository {
  final String? summaryLocation;
  final String? detailLocation;

  _SheetRepo({this.summaryLocation, this.detailLocation})
      : super(now: DateTime(2026, 10, 13));

  @override
  Future<List<MonthlyReviewSummary>> listMonthlyReviews({
    required int year,
    required int month,
    bool mine = false,
    UserRole? scopeRole,
    String? scopeEmployeeId,
    String? scopeManagerId,
    ReviewStage? currentStage,
  }) async =>
      [
        MonthlyReviewSummary(
          id: 'r-$year-$month',
          employeeId: 'e1',
          employeeName: 'Amol Laxman Veer',
          employeeCode: 'VLPL0123',
          year: year,
          month: month,
          monthLabel: '$year-$month',
          currentStage: ReviewStage.selfRating,
          currentStageStatus: StageStatus.inProgress,
          projectLocation: summaryLocation,
        ),
      ];

  @override
  Future<MonthlyReview> getReview(String id) async => MonthlyReview(
        id: id,
        employeeId: 'e1',
        employeeName: 'Amol Laxman Veer',
        employeeCode: 'VLPL0123',
        projectLocation: detailLocation,
        period: const ReviewPeriod(2026, 7),
      );
}
