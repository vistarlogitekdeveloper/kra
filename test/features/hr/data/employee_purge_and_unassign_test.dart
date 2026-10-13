import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/features/hr/data/repositories/api_employee_repository.dart';
import 'package:vistar_app/features/hr/data/repositories/api_kra_assignment_repository.dart';

/// Permanent delete (purge) and KRA unassign.
///
/// Purge is irreversible and never refuses, so the preview is the only
/// safeguard between a tap and losing data — including data on OTHER
/// employees' records, which is the half nobody expects a delete to touch.
/// These tests pin the request shapes and the grouping the dialog depends on.
void main() {
  late RequestOptions captured;

  Dio dioReturning(Map<String, dynamic> data, {int status = 200}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1/kra'));
    dio.httpClientAdapter = _RecordingAdapter(
      onRequest: (o) => captured = o,
      body: {'success': true, 'data': data},
      status: status,
    );
    return dio;
  }

  Map<String, dynamic> impactJson({
    int reviewsAsEmployee = 3,
    int assignmentsOwn = 1,
    int monthlyReviews = 6,
    int reviewsAsManager = 4,
    int assignmentsMade = 12,
    int opsScopesAssigned = 2,
    int subordinates = 5,
  }) =>
      {
        'employeeId': 'e-1',
        'employeeCode': 'EMP-1009',
        'name': 'Rahul Kulkarni',
        'isActive': true,
        'removes': {
          'reviewsAsEmployee': reviewsAsEmployee,
          'assignmentsOwn': assignmentsOwn,
          'monthlyReviews': monthlyReviews,
          'reviewsAsManager': reviewsAsManager,
          'assignmentsMade': assignmentsMade,
          'hrFeedsEntered': 0,
          'accountsFeedsEntered': 0,
          'opsFeedsEntered': 0,
          'opsScopesAssigned': opsScopesAssigned,
          'subordinates': subordinates,
        },
      };

  group('deletion impact', () {
    test('is a GET that deletes nothing', () async {
      final repo = ApiEmployeeRepository(dio: dioReturning(impactJson()));
      await repo.deletionImpact('e-1');

      expect(captured.method, 'GET',
          reason: 'the preview must never be a destructive verb');
      expect(captured.path, '/employees/e-1/deletion-impact');
    });

    test('parses the counts out of `removes`', () async {
      final repo = ApiEmployeeRepository(dio: dioReturning(impactJson()));
      final impact = await repo.deletionImpact('e-1');

      expect(impact.employeeCode, 'EMP-1009');
      expect(impact.name, 'Rahul Kulkarni');
      expect(impact.reviewsAsEmployee, 3);
      expect(impact.monthlyReviews, 6);
      expect(impact.reviewsAsManager, 4);
      expect(impact.subordinates, 5);
    });

    test('keeps OTHER employees\' records in their own group', () async {
      // The dialog leads on this number. Summing it into one total would hide
      // that deleting a manager takes their whole team's ratings with them.
      final repo = ApiEmployeeRepository(dio: dioReturning(impactJson()));
      final impact = await repo.deletionImpact('e-1');

      expect(impact.ownTotal, 3 + 1 + 6);
      expect(impact.marksOnOthersTotal, 4 + 12 + 2);
      expect(impact.touchesOthers, isTrue);
    });

    test('subordinates alone still count as touching others', () async {
      // They are detached rather than deleted, but five people silently losing
      // their manager is still a consequence worth warning about.
      final repo = ApiEmployeeRepository(
          dio: dioReturning(impactJson(
        reviewsAsManager: 0,
        assignmentsMade: 0,
        opsScopesAssigned: 0,
      )));
      final impact = await repo.deletionImpact('e-1');

      expect(impact.marksOnOthersTotal, 0);
      expect(impact.touchesOthers, isTrue, reason: '5 reports are detached');
    });

    test('an all-zero impact is reported as empty', () async {
      final repo = ApiEmployeeRepository(
          dio: dioReturning(impactJson(
        reviewsAsEmployee: 0,
        assignmentsOwn: 0,
        monthlyReviews: 0,
        reviewsAsManager: 0,
        assignmentsMade: 0,
        opsScopesAssigned: 0,
        subordinates: 0,
      )));
      final impact = await repo.deletionImpact('e-1');

      expect(impact.isEmpty, isTrue);
      expect(impact.touchesOthers, isFalse);
    });

    test('a flat payload parses too, matching the dual-read convention',
        () async {
      final repo = ApiEmployeeRepository(
        dio: dioReturning({'employeeId': 'e-1', 'reviewsAsManager': 7}),
      );
      final impact = await repo.deletionImpact('e-1');
      expect(impact.reviewsAsManager, 7);
    });
  });

  group('purge', () {
    test('hits the purge path, not the deactivate one', () async {
      // Sending this to DELETE /employees/:id would silently do the SOFT
      // delete instead — the same verb, a different act.
      final repo = ApiEmployeeRepository(
        dio: dioReturning({
          'deleted': true,
          'employeeId': 'e-1',
          'employeeCode': 'EMP-1009',
          'removed': {'reviewsAsManager': 4, 'subordinates': 5},
        }),
      );
      await repo.purge('e-1');

      expect(captured.method, 'DELETE');
      expect(captured.path, '/employees/e-1/purge');
    });

    test('reports what was ACTUALLY removed, from `removed`', () async {
      // The response key differs from the preview's (`removed` vs `removes`),
      // and these are the real figures — the preview is only an estimate taken
      // before the delete.
      final repo = ApiEmployeeRepository(
        dio: dioReturning({
          'deleted': true,
          'employeeId': 'e-1',
          'removed': {'reviewsAsManager': 4, 'subordinates': 5},
        }),
      );
      final removed = await repo.purge('e-1');

      expect(removed.reviewsAsManager, 4);
      expect(removed.subordinates, 5);
    });
  });

  group('unassign one KRA', () {
    test('deletes the assignment by id', () async {
      final repo = ApiKraAssignmentRepository(
        dio: dioReturning({'deleted': true, 'id': 'a-1'}),
      );
      await repo.unassign('a-1');

      expect(captured.method, 'DELETE');
      expect(captured.path, '/kra-assignments/a-1');
    });

    test('surfaces a review that was KEPT', () async {
      // The user has to be told: the assignment is gone but a scored review
      // is not, and nothing else in the UI would reveal that.
      final repo = ApiKraAssignmentRepository(
        dio: dioReturning({
          'deleted': true,
          'id': 'a-1',
          'reviewRemoved': false,
          'reviewLeftInProgress': true,
        }),
      );
      final result = await repo.unassign('a-1');

      expect(result.reviewLeftInProgress, isTrue);
      expect(result.reviewRemoved, isFalse);
    });
  });

  group('unassign every KRA for an employee', () {
    test('omits cycleId entirely when clearing all cycles', () async {
      // An empty cycleId would scope the call to a cycle with no id and clear
      // nothing, reporting success.
      final repo = ApiKraAssignmentRepository(
        dio:
            dioReturning({'deletedCount': 2, 'employeeId': 'e-1', 'items': []}),
      );
      await repo.unassignAllForEmployee('e-1');

      expect(captured.path, '/kra-assignments/employee/e-1');
      expect(captured.queryParameters.containsKey('cycleId'), isFalse);
    });

    test('passes cycleId when scoped to one cycle', () async {
      final repo = ApiKraAssignmentRepository(
        dio: dioReturning({'deletedCount': 1, 'items': []}),
      );
      await repo.unassignAllForEmployee('e-1', cycleId: 'c-9');

      expect(captured.queryParameters['cycleId'], 'c-9');
    });

    test('counts the reviews left behind', () async {
      final repo = ApiKraAssignmentRepository(
        dio: dioReturning({
          'deletedCount': 3,
          'items': [
            {'deleted': true, 'id': 'a-1', 'reviewLeftInProgress': true},
            {'deleted': true, 'id': 'a-2', 'reviewRemoved': true},
            {'deleted': true, 'id': 'a-3', 'reviewLeftInProgress': true},
          ],
        }),
      );
      final result = await repo.unassignAllForEmployee('e-1');

      expect(result.deletedCount, 3);
      expect(result.reviewsLeftInProgress, 2);
    });

    test('zero is a success, not a failure', () async {
      final repo = ApiKraAssignmentRepository(
        dio: dioReturning({'deletedCount': 0, 'items': []}),
      );
      final result = await repo.unassignAllForEmployee('e-1');
      expect(result.deletedCount, 0);
      expect(result.items, isEmpty);
    });
  });

  group('impact copy', () {
    test('counts agree with their nouns', () {
      expect(AppStrings.countOf(1, 'review', 'reviews'), '1 review');
      expect(AppStrings.countOf(3, 'review', 'reviews'), '3 reviews');
      expect(AppStrings.countOf(0, 'review', 'reviews'), '0 reviews');
    });

    test('the detach line names the consequence, not just the number', () {
      final one = AppStrings.employeePurgeDetaches(1);
      expect(one, contains('1 direct report'));
      expect(one, contains('without a manager'));
      expect(AppStrings.employeePurgeDetaches(5), contains('5 direct reports'));
    });

    test('the other-employees warning explains whose data it is', () {
      // A bare count here reads as more of the same employee's records.
      expect(AppStrings.employeePurgeOthersWhy, contains('other employees'));
      expect(AppStrings.employeePurgeOthersHeading.toUpperCase(),
          contains('OTHER'));
    });
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  final void Function(RequestOptions) onRequest;
  final Map<String, dynamic> body;
  final int status;
  _RecordingAdapter({
    required this.onRequest,
    required this.body,
    this.status = 200,
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onRequest(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
