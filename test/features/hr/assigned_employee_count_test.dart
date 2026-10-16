import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/features/hr/data/models/employee.dart';
import 'package:vistar_app/features/hr/data/models/hr_dashboard_models.dart';
import 'package:vistar_app/features/hr/data/models/kra_assignment.dart';
import 'package:vistar_app/features/hr/data/repositories/employee_repository.dart';
import 'package:vistar_app/features/hr/data/repositories/kra_assignment_repository.dart';
import 'package:vistar_app/features/hr/presentation/providers/employee_providers.dart';
import 'package:vistar_app/features/hr/presentation/providers/hr_dashboard_providers.dart';
import 'package:vistar_app/features/hr/presentation/providers/kra_assignment_providers.dart';

/// "KRAs Assigned — N of M" on the HR home grid.
///
/// Reported as the dashboard's numbers not making sense: 42 active employees
/// beside 44 pending reviews reads as broken arithmetic. It is not — a cycle
/// has a review per employee per month — but nothing on the screen said how
/// many of those 42 hold KRAs at all, and an employee with none generates no
/// review and earns no incentive.
///
/// Two counting rules carry the whole card, and getting either wrong produces a
/// number that looks plausible:
///
///   * DISTINCT employees. An employee may hold several assignments (one per
///     template), so counting rows reports more assigned employees than the
///     organisation employs — the same shape of error as the stale
///     `activeEmployees` figure this card sits next to.
///   * scoped to the cycle under review. An assignment from a closed cycle is
///     history; counting it claims coverage this quarter does not have.
void main() {
  KraAssignment assignment(String id, String employeeId, String cycleId) =>
      KraAssignment(
        id: id,
        employeeId: employeeId,
        cycleId: cycleId,
        items: const [],
        isLocked: false,
      );

  Future<({int assigned, int active})> count({
    required List<KraAssignment> assignments,
    required int activeTotal,
    String? activeCycleId = 'cyc-now',
  }) async {
    final container = ProviderContainer(overrides: [
      kraAssignmentRepositoryProvider
          .overrideWithValue(_FakeAssignments(assignments)),
      employeeRepositoryProvider.overrideWithValue(_FakeEmployees(activeTotal)),
      hrActiveCycleProvider.overrideWith(
        (ref) async => activeCycleId == null
            ? null
            : HrActiveCycle(
                id: activeCycleId,
                name: 'Q2 FY2026-27',
                status: 'ACTIVE',
                startDate: DateTime(2026, 7),
                endDate: DateTime(2026, 9, 30),
              ),
      ),
    ]);
    addTearDown(container.dispose);
    return container.read(hrAssignedEmployeeCountProvider.future);
  }

  test('an employee with several assignments is counted once', () async {
    // The reported failure mode in miniature: three rows, two people.
    final c = await count(
      assignments: [
        assignment('a1', 'emp1', 'cyc-now'),
        assignment('a2', 'emp1', 'cyc-now'),
        assignment('a3', 'emp2', 'cyc-now'),
      ],
      activeTotal: 42,
    );

    expect(c.assigned, 2, reason: 'distinct employees, not assignment rows');
    expect(c.active, 42);
  });

  test('assignments from another cycle do not count', () async {
    // Coverage is a statement about the quarter being reviewed. A closed
    // cycle's assignment would claim this one has KRAs it does not.
    final c = await count(
      assignments: [
        assignment('a1', 'emp1', 'cyc-now'),
        assignment('a2', 'emp2', 'cyc-old'),
        assignment('a3', 'emp3', 'cyc-old'),
      ],
      activeTotal: 42,
    );

    expect(c.assigned, 1);
  });

  test('with no active cycle, every assignment counts', () async {
    // The only honest answer when there is no cycle to scope to — reporting
    // zero would read as "nobody is assigned", which is a different claim.
    final c = await count(
      assignments: [
        assignment('a1', 'emp1', 'cyc-old'),
        assignment('a2', 'emp2', 'cyc-older'),
      ],
      activeTotal: 42,
      activeCycleId: null,
    );

    expect(c.assigned, 2);
  });

  test('nobody assigned is zero, and that is a real answer', () async {
    final c = await count(assignments: const [], activeTotal: 42);
    expect(c.assigned, 0);
    expect(c.active, 42);
  });

  test('the active count comes from the roster, not the overview', () async {
    // hrActiveEmployeeCountProvider exists because the backend overview's
    // activeEmployees was observed at 6 against a 26-strong roster. This card
    // must read the same authoritative source as the card beside it, or the
    // two will disagree on screen.
    final c = await count(
      assignments: [assignment('a1', 'emp1', 'cyc-now')],
      activeTotal: 26,
    );

    expect(c.active, 26);
  });

  group('the copy', () {
    test('reads as coverage, not as a fraction', () {
      expect(AppStrings.hrKpiAssignedOf(38, 42), '38 of 42');
      expect(AppStrings.hrKpiAssignedEmployees, 'KRAs Assigned');
    });

    test('a complete roster still reads naturally', () {
      expect(AppStrings.hrKpiAssignedOf(42, 42), '42 of 42');
    });
  });
}

class _FakeAssignments implements KraAssignmentRepository {
  final List<KraAssignment> _all;
  _FakeAssignments(this._all);

  @override
  Future<List<KraAssignment>> list({String? employeeId}) async => _all;

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName}');
}

class _FakeEmployees implements EmployeeRepository {
  final int _activeTotal;
  _FakeEmployees(this._activeTotal);

  @override
  Future<EmployeePage> list({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? role,
    bool? isActive,
  }) async {
    // The provider asks for the envelope's total only, with isActive: true.
    expect(isActive, isTrue, reason: 'the card counts ACTIVE employees');
    return EmployeePage(
      employees: const [],
      total: _activeTotal,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName}');
}
