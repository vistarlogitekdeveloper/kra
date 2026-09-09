import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/org_scope_provider.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/incentive_summary.dart';
import '../../data/repositories/api_my_incentive_repository.dart';
import '../../data/repositories/my_incentive_repository.dart';

final myIncentiveRepositoryProvider = Provider<MyIncentiveRepository>((ref) {
  // Org-scoped: recreated whenever the caller switches organisation, which
  // invalidates every provider that watches this repository. Without it,
  // cached lists from the previous tenant would be served under the new
  // tenant's name. See core/providers/org_scope_provider.dart.
  ref.watch(currentOrgIdProvider);
  return ApiMyIncentiveRepository(dio: ref.read(dioProvider));
});

/// Quarterly incentive snapshot. Keyed by cycleId — the backend
/// requires the param so passing nulls / empty strings is a caller
/// error and will surface as a 400 from the server. autoDispose
/// to free the snapshot when the user leaves the relevant tab.
final myIncentiveSummaryProvider = FutureProvider.autoDispose
    .family<IncentiveSummary, String>((ref, cycleId) async {
  final repo = ref.watch(myIncentiveRepositoryProvider);
  return repo.fetchIncentiveSummary(cycleId: cycleId);
});
