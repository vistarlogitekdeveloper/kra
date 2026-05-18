import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/incentive_summary.dart';
import '../../data/repositories/api_my_incentive_repository.dart';
import '../../data/repositories/my_incentive_repository.dart';

final myIncentiveRepositoryProvider = Provider<MyIncentiveRepository>((ref) {
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
