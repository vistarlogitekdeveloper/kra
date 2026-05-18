import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/employee_dashboard.dart';
import '../../data/repositories/api_employee_dashboard_repository.dart';
import '../../data/repositories/employee_dashboard_repository.dart';

/// Single SWAP point — replace the body to drop in a fake.
final employeeDashboardRepositoryProvider =
    Provider<EmployeeDashboardRepository>((ref) {
  return ApiEmployeeDashboardRepository(dio: ref.read(dioProvider));
});

/// Home-screen aggregate fetch. autoDispose so we don't keep a stale
/// snapshot in memory after the user navigates away from the home tab.
/// The home screen invalidates this on pull-to-refresh.
final employeeDashboardProvider =
    FutureProvider.autoDispose<EmployeeDashboard>((ref) async {
  final repo = ref.watch(employeeDashboardRepositoryProvider);
  return repo.fetchDashboard();
});
