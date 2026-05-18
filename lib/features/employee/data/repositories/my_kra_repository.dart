import '../models/my_kra_assignment.dart';

/// Contract for fetching the logged-in employee's own KRA assignments.
///
/// The backend filters by employeeId from the auth token — no
/// employeeId param is needed (or accepted) here.
abstract class MyKraRepository {
  /// Lists my assignments. Filter by [cycleId] to scope to one cycle;
  /// pass `null` for "all cycles" (the backend returns the active
  /// cycle's assignments by default in that case).
  Future<List<MyKraAssignment>> listMyAssignments({String? cycleId});
}
