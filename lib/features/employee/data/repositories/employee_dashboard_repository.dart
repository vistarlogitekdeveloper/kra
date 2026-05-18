import '../models/employee_dashboard.dart';

/// Contract for the home-screen aggregate fetch.
///
/// One round-trip → everything the home tab needs. UI binds to this
/// abstract; drop in a fake implementation by registering a different
/// provider in tests.
abstract class EmployeeDashboardRepository {
  /// Fetches the full home-screen payload. Throws [ApiError] on any
  /// transport / envelope failure.
  Future<EmployeeDashboard> fetchDashboard();
}
