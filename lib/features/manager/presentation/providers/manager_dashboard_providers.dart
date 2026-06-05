import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/manager_dashboard.dart';
import '../../data/repositories/api_manager_dashboard_repository.dart';
import '../../data/repositories/manager_dashboard_repository.dart';

final managerDashboardRepositoryProvider =
    Provider<ManagerDashboardRepository>((ref) {
  return ApiManagerDashboardRepository(dio: ref.read(dioProvider));
});

/// Single-shot fetch for the dashboard payload. autoDispose so the
/// payload is refetched whenever the user re-enters the dashboard
/// tab — fresh pending-actions list every visit.
final managerDashboardProvider =
    FutureProvider.autoDispose<ManagerDashboard>((ref) {
  return ref.watch(managerDashboardRepositoryProvider).fetchDashboard();
});
