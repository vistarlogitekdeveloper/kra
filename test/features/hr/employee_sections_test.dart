import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/models/employee.dart';
import 'package:vistar_app/features/hr/data/repositories/employee_repository.dart';
import 'package:vistar_app/features/hr/presentation/providers/employee_providers.dart';

/// The Employees screen has two sections, Active and Deactivated, and a
/// deactivated employee is shown only under Deactivated.
///
/// It used to open on "Any status" — which sent no filter, so the server fell
/// back to active-only anyway — and a deleted row stayed in the list, greyed
/// out, until the next refresh. That lingering row is what read as
/// "deactivated employees are still displayed".
void main() {
  Employee emp(String id, {bool active = true}) => Employee(
        id: id,
        employeeCode: 'VLPL$id',
        fullName: 'Employee $id',
        email: '$id@vistarlogitek.com',
        role: 'EMPLOYEE',
        isActive: active,
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('the screen opens on the Active section', () {
    expect(const EmployeeFilter().isActive, isTrue);
  });

  test('each section asks the server for exactly its own employees', () async {
    final repo = _FakeEmployees([emp('1'), emp('2', active: false)]);

    EmployeeListController(repository: repo, filter: const EmployeeFilter());
    await settle();
    expect(repo.lastIsActive, isTrue);

    final deactivated = EmployeeListController(
      repository: repo,
      filter: const EmployeeFilter(isActive: false),
    );
    await settle();
    expect(repo.lastIsActive, isFalse);
    expect(deactivated.state.employees.map((e) => e.id), ['2']);
  });

  test('a deleted employee leaves the Active list at once', () async {
    final repo = _FakeEmployees([emp('1'), emp('2')]);
    final active =
        EmployeeListController(repository: repo, filter: const EmployeeFilter());
    await settle();

    expect(await active.deactivateOptimistic('1'), isNull);
    expect(active.state.employees.map((e) => e.id), ['2']);
    expect(active.state.total, 1);
    expect(repo.deactivated, ['1']);
  });

  test('a reactivated employee leaves the Deactivated list at once', () async {
    final repo = _FakeEmployees([emp('3', active: false)]);
    final deactivated = EmployeeListController(
      repository: repo,
      filter: const EmployeeFilter(isActive: false),
    );
    await settle();

    expect(await deactivated.reactivate('3'), isNull);
    expect(deactivated.state.employees, isEmpty);
    expect(repo.updates, [
      {'id': '3', 'changes': {'isActive': true}},
    ]);
  });

  test('a failed reactivation keeps the row and says why', () async {
    final repo = _FakeEmployees([emp('3', active: false)], failUpdate: true);
    final deactivated = EmployeeListController(
      repository: repo,
      filter: const EmployeeFilter(isActive: false),
    );
    await settle();

    expect(await deactivated.reactivate('3'), isNotNull);
    expect(deactivated.state.employees.map((e) => e.id), ['3']);
  });
}

class _FakeEmployees implements EmployeeRepository {
  _FakeEmployees(this.all, {this.failUpdate = false});

  final List<Employee> all;
  final bool failUpdate;
  bool? lastIsActive;
  final List<String> deactivated = [];
  final List<Map<String, Object>> updates = [];

  @override
  Future<EmployeePage> list({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? role,
    bool? isActive,
  }) async {
    lastIsActive = isActive;
    final rows =
        all.where((e) => isActive == null || e.isActive == isActive).toList();
    return EmployeePage(
        employees: rows, page: page, pageSize: pageSize, total: rows.length);
  }

  @override
  Future<void> deactivate(String id) async => deactivated.add(id);

  @override
  Future<Employee> update(String id, Map<String, dynamic> changes) async {
    if (failUpdate) throw Exception('server down');
    updates.add({'id': id, 'changes': changes});
    return all.firstWhere((e) => e.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
