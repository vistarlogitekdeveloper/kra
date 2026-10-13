import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/features/hr/data/models/employee.dart';
import 'package:vistar_app/features/hr/data/models/employee_deletion_impact.dart';
import 'package:vistar_app/features/hr/data/models/kra_assignment.dart';
import 'package:vistar_app/features/hr/data/repositories/employee_repository.dart';
import 'package:vistar_app/features/hr/data/repositories/kra_assignment_repository.dart';
import 'package:vistar_app/features/hr/presentation/providers/employee_providers.dart';
import 'package:vistar_app/features/hr/presentation/providers/kra_assignment_providers.dart';
import 'package:vistar_app/features/hr/presentation/screens/employee_detail_screen.dart';

/// Permanent delete against a backend that does not have the purge routes.
///
/// Reported as "the backend is not connected to employee deletion": the
/// preview answered 404 because `/employees/:id/deletion-impact` is not
/// deployed, and the screen said only "Could not check what this would
/// remove" — which reads as a transient fault worth retrying.
///
/// The second half is the dangerous one. 404 on `DELETE /:id/purge` was taken
/// to mean "somebody already deleted them", so a server with NO SUCH ROUTE
/// produced the full success path: "Employee deleted.", the list invalidated,
/// the screen popped — over an employee still sitting in the database. An
/// unmounted Express route and a missing row answer with the same status and
/// the same `RES_001`, so the status cannot settle it; only asking can.
void main() {
  const notFound = ApiError(
    type: ApiErrorType.notFound,
    code: 'RES_001',
    message: 'Route DELETE /api/v1/kra/employees/e-1/purge not found',
    statusCode: 404,
  );
  const serverDown = ApiError(
    type: ApiErrorType.server,
    code: 'SRV_001',
    message: 'Internal server error',
    statusCode: 500,
  );

  const employee = Employee(
    id: 'e-1',
    employeeCode: 'VLPL0123',
    fullName: 'Amol Laxman Veer',
    email: 'amol@vistar.test',
    role: 'EMPLOYEE',
  );

  Future<void> pump(WidgetTester tester, _FakeEmployees repo) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        employeeRepositoryProvider.overrideWithValue(repo),
        kraAssignmentRepositoryProvider.overrideWithValue(_NoAssignments()),
      ],
      child: MaterialApp.router(
        // A route BELOW the screen, because the success path pops back to the
        // employee list. Without one the pop throws and the test would fail
        // for a reason that has nothing to do with the delete.
        routerConfig: GoRouter(
          initialLocation: '/employees/e-1',
          routes: [
            GoRoute(
              path: '/employees',
              builder: (_, __) => const Scaffold(body: Text('list')),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, __) =>
                      const EmployeeDetailScreen(employeeId: 'e-1'),
                ),
              ],
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Taps "Delete permanently" and, when the preview succeeded, confirms.
  Future<void> deletePermanently(WidgetTester tester,
      {bool expectDialog = true}) async {
    final action = find.text(AppStrings.employeePurgeAction);
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    if (!expectDialog) return;
    await tester.tap(find.text(AppStrings.employeePurgeConfirm));
    await tester.pumpAndSettle();
  }

  testWidgets('a preview that 404s names the deploy, not a retry',
      (tester) async {
    final repo = _FakeEmployees(employee, impactError: notFound);
    await pump(tester, repo);
    await deletePermanently(tester, expectDialog: false);

    expect(find.textContaining('not available on this server yet'),
        findsOneWidget);
    // And it never reaches the confirmation, so nothing can be deleted.
    expect(find.text(AppStrings.employeePurgeConfirm), findsNothing);
  });

  testWidgets(
      'a preview that fails for another reason says what the server '
      'said', (tester) async {
    // The missing-API copy must not swallow real failures — a 500 here is not
    // a deploy problem and telling the user it is would misdirect them.
    final repo = _FakeEmployees(employee, impactError: serverDown);
    await pump(tester, repo);
    await deletePermanently(tester, expectDialog: false);

    expect(find.text('Internal server error'), findsOneWidget);
    expect(
        find.textContaining('not available on this server yet'), findsNothing);
  });

  group('a 404 from the delete itself', () {
    testWidgets('with the employee STILL THERE is a failure, not a success',
        (tester) async {
      // The reported bug in its worst form. Nothing was deleted, so nothing
      // may be reported as deleted.
      final repo = _FakeEmployees(employee, purgeError: notFound);
      await pump(tester, repo);
      await deletePermanently(tester);

      expect(find.text(AppStrings.employeePurgeSuccess), findsNothing);
      expect(find.textContaining('not available on this server yet'),
          findsOneWidget);
      expect(repo.reReads, 1, reason: 'the 404 has to be checked, not assumed');
    });

    testWidgets('with the employee GONE is the success it always was',
        (tester) async {
      // Somebody removed them between the preview and the delete. That is the
      // end state the user asked for, and the old behaviour here was right.
      final repo =
          _FakeEmployees(employee, purgeError: notFound, goneAfterPurge: true);
      await pump(tester, repo);
      await deletePermanently(tester);

      expect(find.text(AppStrings.employeePurgeSuccess), findsOneWidget);
    });

    testWidgets('that cannot be checked is reported as unconfirmed',
        (tester) async {
      // The re-read failed for its own reason. Neither reading is established,
      // and a destructive act claimed without evidence is the worse error.
      final repo = _FakeEmployees(employee,
          purgeError: notFound, reReadError: serverDown);
      await pump(tester, repo);
      await deletePermanently(tester);

      expect(find.text(AppStrings.employeePurgeSuccess), findsNothing);
      expect(find.text(AppStrings.employeePurgeUnconfirmed), findsOneWidget);
    });
  });
}

/// Serves one employee, and fails the preview, the delete or the re-read on
/// demand. [reReads] counts the getById calls made AFTER the delete.
class _FakeEmployees implements EmployeeRepository {
  _FakeEmployees(
    this.employee, {
    this.impactError,
    this.purgeError,
    this.reReadError,
    this.goneAfterPurge = false,
  });

  final Employee employee;
  final Object? impactError;
  final Object? purgeError;
  final Object? reReadError;
  final bool goneAfterPurge;

  bool _purgeAttempted = false;
  int reReads = 0;

  @override
  Future<Employee> getById(String id) async {
    if (!_purgeAttempted) return employee;
    reReads++;
    if (reReadError != null) throw reReadError!;
    if (goneAfterPurge) {
      throw const ApiError(
        type: ApiErrorType.notFound,
        code: 'RES_001',
        message: 'Employee not found',
        statusCode: 404,
      );
    }
    return employee;
  }

  @override
  Future<EmployeeDeletionImpact> deletionImpact(String id) async {
    if (impactError != null) throw impactError!;
    return const EmployeeDeletionImpact(employeeId: 'e-1');
  }

  @override
  Future<EmployeeDeletionImpact> purge(String id) async {
    _purgeAttempted = true;
    if (purgeError != null) throw purgeError!;
    return const EmployeeDeletionImpact(employeeId: 'e-1');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _NoAssignments implements KraAssignmentRepository {
  @override
  Future<List<KraAssignment>> list({String? employeeId}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
