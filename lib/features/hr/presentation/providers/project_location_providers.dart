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

/// Every location (active or not) for the HR management screen. Kept
/// separate from [allProjectLocationsProvider] so the dropdown cache and
/// the editable list invalidate independently.
final allLocationsForManagementProvider =
    FutureProvider.autoDispose<List<ProjectLocation>>((ref) async {
  final repo = ref.watch(projectLocationsRepositoryProvider);
  return repo.listAll();
});

/// Create / update / delete actions for locations. Each mutation
/// invalidates both the management list and the active-locations cache
/// so dependent dropdowns refresh too.
class LocationActions {
  final Ref ref;
  LocationActions(this.ref);

  ProjectLocationsRepository get _repo =>
      ref.read(projectLocationsRepositoryProvider);

  Future<void> create({
    required String name,
    String? code,
    String? city,
    String? state,
    String? address,
    String? customer,
  }) async {
    await _repo.create(
      name: name,
      code: code,
      city: city,
      state: state,
      address: address,
      customer: customer,
    );
    _invalidate();
  }

  Future<void> update(String id, Map<String, dynamic> changes) async {
    await _repo.update(id, changes);
    _invalidate();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    _invalidate();
  }

  void _invalidate() {
    ref.invalidate(allLocationsForManagementProvider);
    ref.invalidate(allProjectLocationsProvider);
  }
}

final locationActionsProvider =
    Provider<LocationActions>((ref) => LocationActions(ref));
