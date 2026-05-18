import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/manager_dashboard.dart';
// ignore: unused_import
import '../../data/repositories/api_manager_dashboard_repository.dart';
import '../../data/repositories/manager_dashboard_repository.dart';
import '../../data/repositories/mock_manager_dashboard_repository.dart';

/// Repository binding for the manager dashboard.
///
/// Defaults to [MockManagerDashboardRepository] so the app boots
/// without a live backend. Swap to the API implementation by changing
/// the body to:
///
/// ```dart
/// return ApiManagerDashboardRepository(dio: ref.read(dioProvider));
/// ```
///
/// `ref.read(dioProvider)` stays imported so the swap is one line.
final managerDashboardRepositoryProvider =
    Provider<ManagerDashboardRepository>((ref) {
  // ignore: unused_local_variable
  final dio = ref.read(dioProvider);
  return const MockManagerDashboardRepository();
  // return ApiManagerDashboardRepository(dio: dio);
});

/// Single-shot fetch for the dashboard payload. autoDispose so the
/// payload is refetched whenever the user re-enters the dashboard
/// tab — fresh pending-actions list every visit.
final managerDashboardProvider =
    FutureProvider.autoDispose<ManagerDashboard>((ref) {
  return ref.watch(managerDashboardRepositoryProvider).fetchDashboard();
});
