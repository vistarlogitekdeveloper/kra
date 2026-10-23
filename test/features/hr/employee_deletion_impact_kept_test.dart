import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/models/employee_deletion_impact.dart';

/// Permanent delete now KEEPS what the person entered on other employees'
/// records (re-attributed to whoever deletes). The API says so with
/// `removes.marksOnOthersKept`; the dialog then drops its red "this removes
/// that work from those employees" warning. An API without the flag still
/// deletes them, so the warning stays.
void main() {
  Map<String, dynamic> impact({bool? kept, int subordinates = 0}) => {
        'employeeId': 'e1',
        'removes': {
          'reviewsAsManager': 12,
          'hrFeedsEntered': 3,
          'subordinates': subordinates,
          if (kept != null) 'marksOnOthersKept': kept,
        },
      };

  test('an API that keeps the marks: not a loss to other employees', () {
    final i = EmployeeDeletionImpact.fromJson(impact(kept: true));
    expect(i.marksOnOthersKept, isTrue);
    expect(i.marksOnOthersTotal, 15);
    expect(i.touchesOthers, isFalse);
  });

  test('an older API (no flag) still deletes them: keep the warning', () {
    final i = EmployeeDeletionImpact.fromJson(impact());
    expect(i.marksOnOthersKept, isFalse);
    expect(i.touchesOthers, isTrue);
  });

  test('detached reports still count as touching others', () {
    final i = EmployeeDeletionImpact.fromJson(impact(kept: true, subordinates: 2));
    expect(i.touchesOthers, isTrue);
  });
}
