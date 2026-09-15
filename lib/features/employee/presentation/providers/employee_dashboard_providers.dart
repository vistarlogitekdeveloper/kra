import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/org_scope_provider.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/employee_dashboard.dart';
import '../../data/repositories/api_employee_dashboard_repository.dart';
import '../../data/repositories/employee_dashboard_repository.dart';

/// Single SWAP point — replace the body to drop in a fake.
final employeeDashboardRepositoryProvider =
    Provider<EmployeeDashboardRepository>((ref) {
  // Org-scoped: recreated whenever the caller switches organisation, which
  // invalidates every provider that watches this repository. Without it,
  // cached lists from the previous tenant would be served under the new
  // tenant's name. See core/providers/org_scope_provider.dart.
  ref.watch(currentOrgIdProvider);
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
