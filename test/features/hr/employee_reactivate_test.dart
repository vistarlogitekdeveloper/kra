import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/features/hr/data/models/employee.dart';
import 'package:vistar_app/features/hr/data/repositories/employee_repository.dart';
import 'package:vistar_app/features/hr/presentation/providers/employee_providers.dart';
import 'package:vistar_app/features/hr/presentation/widgets/employee_list_tile.dart';

/// Restoring a deleted (deactivated) employee.
///
/// Delete is a soft delete, and its own confirmation tells the user the record
/// "can be restored if this was a mistake" — until now nothing in the app
/// could. These assertions cover the three places that promise would break:
/// the row the list shows after the call, the menu that offers the action, and
/// the message shown when the server refuses.
void main() {
  Employee employee({bool isActive = false}) => Employee(
        id: 'emp-1',
        employeeCode: 'VLPL1436',
        fullName: 'Ganga Jha',
        email: 'ganga@vistar.test',
        role: 'EMPLOYEE',
        isActive: isActive,
      );

  ApiError conflict(String message) => ApiError(
        type: ApiErrorType.server,
        code: 'CONFLICT',
        message: message,
        statusCode: 409,
      );

  group('reactivateFailureReason', () {
    test('"already active" tells the user to refresh, not to retry', () {
      final reason =
          reactivateFailureReason(conflict('Employee is already active'));

      expect(reason, AppStrings.employeesReactivateAlreadyActive);
      // A retry can never clear this one: the server is already in the state
      // being asked for, and the list on screen is what is wrong.
      expect(reason.toLowerCase(), contains('refresh'));
      expect(reason, isNot(AppStrings.employeesReactivateFailed));
    });

    test('an unrecognised server message is shown verbatim', () {
      expect(
        reactivateFailureReason(conflict('Employee not found')),
        'Employee not found',
      );
    });

    test('a non-API failure falls back to the generic message', () {
      expect(
        reactivateFailureReason(Exception('socket closed')),
        AppStrings.employeesReactivateFailed,
      );
    });

    test('an empty server message falls back rather than showing nothing', () {
      expect(
        reactivateFailureReason(conflict('')),
        AppStrings.employeesReactivateFailed,
      );
    });
  });

  group('reactivateOptimistic', () {
    test('shows the row the SERVER returns, not the optimistic guess',
        () async {
      // The server's copy carries fields the local patch could not know about
      // — here the manager the restore brought back into view. Keeping the
      // patched copy would show a row that no longer matches the record.
      const restored = Employee(
        id: 'emp-1',
        employeeCode: 'VLPL1436',
        fullName: 'Ganga Jha',
        email: 'ganga@vistar.test',
        role: 'EMPLOYEE',
        managerName: 'Asha Rao',
        isActive: true,
      );
      final repo = _FakeEmployees([employee()], restored: restored);
      final controller = EmployeeListController(
        repository: repo,
        filter: const EmployeeFilter(),
      );
      await pumpEventQueue();

      final failure = await controller.reactivateOptimistic('emp-1');

      expect(failure, isNull);
      expect(repo.reactivated, ['emp-1']);
      expect(controller.state.employees.single.isActive, isTrue);
      expect(controller.state.employees.single.managerName, 'Asha Rao');
    });

    test('a refusal puts the row back as it was', () async {
      final repo = _FakeEmployees(
        [employee()],
        error: conflict('Employee is already active'),
      );
      final controller = EmployeeListController(
        repository: repo,
        filter: const EmployeeFilter(),
      );
      await pumpEventQueue();

      final failure = await controller.reactivateOptimistic('emp-1');

      expect(failure, AppStrings.employeesReactivateAlreadyActive);
      // The optimistic flip is undone: the row still reads Inactive, which is
      // what the server holds.
      expect(controller.state.employees.single.isActive, isFalse);
    });

    test('an employee who is not in the list is still restored', () async {
      // The detail screen reaches this for an employee the list never loaded
      // (a deep link, or a list filtered to active only). Refusing there would
      // report a failure for a restore that was never attempted — the bug the
      // deactivate path still has.
      final repo = _FakeEmployees(const [], restored: employee(isActive: true));
      final controller = EmployeeListController(
        repository: repo,
        filter: const EmployeeFilter(),
      );
      await pumpEventQueue();

      final failure = await controller.reactivateOptimistic('emp-1');

      expect(failure, isNull);
      expect(repo.reactivated, ['emp-1']);
    });
  });

  group('EmployeeListTile menu', () {
    Future<void> openMenu(WidgetTester tester, Employee e) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmployeeListTile(
            employee: e,
            onEdit: () {},
            onDeactivate: () {},
            onReactivate: () {},
          ),
        ),
      ));
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
    }

    testWidgets('an inactive employee is offered Restore, not Delete',
        (tester) async {
      await openMenu(tester, employee());

      expect(find.text(AppStrings.employeesActionReactivate), findsOneWidget);
      expect(find.text(AppStrings.employeesActionDeactivate), findsNothing);
    });

    testWidgets('an active employee is offered Delete, not Restore',
        (tester) async {
      await openMenu(tester, employee(isActive: true));

      expect(find.text(AppStrings.employeesActionDeactivate), findsOneWidget);
      expect(find.text(AppStrings.employeesActionReactivate), findsNothing);
    });

    testWidgets('Restore fires the callback', (tester) async {
      var fired = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmployeeListTile(
            employee: employee(),
            onReactivate: () => fired++,
          ),
        ),
      ));
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.employeesActionReactivate));
      await tester.pumpAndSettle();

      expect(fired, 1);
    });
  });
}

/// Serves one page of employees and records the restores it was asked for.
class _FakeEmployees implements EmployeeRepository {
  _FakeEmployees(this._page, {this.restored, this.error});

  final List<Employee> _page;
  final Employee? restored;
  final Object? error;
  final List<String> reactivated = [];

  @override
  Future<EmployeePage> list({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? role,
    bool? isActive,
  }) async =>
      EmployeePage(
        employees: _page,
        total: _page.length,
        page: page,
        pageSize: pageSize,
      );

  @override
  Future<Employee> reactivate(String id) async {
    if (error != null) throw error!;
    reactivated.add(id);
    return restored!;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName}');
}
