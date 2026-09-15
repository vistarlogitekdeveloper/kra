import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/repositories/deadline_schedule_repository.dart';

/// Reads the backend's resolved deadline schedule. See [DeadlineSchedule].
final deadlineScheduleRepositoryProvider =
    Provider<DeadlineScheduleRepository>((ref) {
  return ApiDeadlineScheduleRepository(dio: ref.watch(dioProvider));
});
