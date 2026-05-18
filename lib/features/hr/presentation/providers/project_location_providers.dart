import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/project_location.dart';
import '../../data/repositories/project_locations_repository.dart';

final projectLocationsRepositoryProvider =
    Provider<ProjectLocationsRepository>((ref) {
  return ApiProjectLocationsRepository(dio: ref.read(dioProvider));
});

/// All active project locations, fetched once and cached for the lifetime
/// of any screen that watches them. Keeps the dropdown snappy without a
/// per-open round-trip.
final allProjectLocationsProvider =
    FutureProvider<List<ProjectLocation>>((ref) async {
  final repo = ref.watch(projectLocationsRepositoryProvider);
  return repo.listActive();
});
