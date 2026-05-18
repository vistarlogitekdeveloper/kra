import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/kra_template.dart';
import '../../data/repositories/api_kra_template_repository.dart';
import '../../data/repositories/kra_template_repository.dart';

final kraTemplateRepositoryProvider = Provider<KraTemplateRepository>((ref) {
  return ApiKraTemplateRepository(dio: ref.read(dioProvider));
});

/// Filter for the templates list — narrowed by role.
class KraTemplateFilter {
  final String? role;
  final bool? isActive;
  const KraTemplateFilter({this.role, this.isActive = true});

  KraTemplateFilter copyWith({String? role, Object? isActive = _sentinel}) {
    return KraTemplateFilter(
      role: role ?? this.role,
      isActive: identical(isActive, _sentinel)
          ? this.isActive
          : isActive as bool?,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) =>
      other is KraTemplateFilter &&
      other.role == role &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(role, isActive);
}

class KraTemplateFilterController extends StateNotifier<KraTemplateFilter> {
  KraTemplateFilterController() : super(const KraTemplateFilter());
  void setRole(String? role) => state = state.copyWith(role: role);
  void setActive(bool? isActive) => state = state.copyWith(isActive: isActive);
  void reset() => state = const KraTemplateFilter();
}

final kraTemplateFilterProvider =
    StateNotifierProvider<KraTemplateFilterController, KraTemplateFilter>(
  (ref) => KraTemplateFilterController(),
);

/// All templates matching the current filter. Read-only — mutations go
/// through [kraTemplateActionsProvider] which invalidates this on success.
final kraTemplatesProvider =
    FutureProvider.autoDispose<List<KraTemplate>>((ref) async {
  final filter = ref.watch(kraTemplateFilterProvider);
  final repo = ref.watch(kraTemplateRepositoryProvider);
  return repo.list(role: filter.role, isActive: filter.isActive);
});

/// Per-template detail fetch (with items[]). Used by the edit form.
final kraTemplateDetailProvider =
    FutureProvider.autoDispose.family<KraTemplate, String>((ref, id) async {
  final repo = ref.watch(kraTemplateRepositoryProvider);
  return repo.getById(id);
});

/// Actions namespace — every mutation invalidates the list provider so
/// the screen re-renders with fresh data on the next read.
class KraTemplateActions {
  final Ref ref;
  KraTemplateActions(this.ref);

  KraTemplateRepository get _repo => ref.read(kraTemplateRepositoryProvider);

  Future<KraTemplate> create(KraTemplate template) async {
    final created = await _repo.create(
      name: template.name,
      role: template.role,
      description: template.description,
      items: template.items,
    );
    ref.invalidate(kraTemplatesProvider);
    return created;
  }

  Future<KraTemplate> update(String id, KraTemplate template) async {
    final updated = await _repo.update(id, {
      'name': template.name,
      'role': template.role,
      'description': template.description,
      'items': template.items.map((e) => e.toJson()).toList(),
    });
    ref.invalidate(kraTemplatesProvider);
    ref.invalidate(kraTemplateDetailProvider(id));
    return updated;
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    ref.invalidate(kraTemplatesProvider);
  }

  Future<KraTemplate> clone(String id) async {
    final cloned = await _repo.clone(id);
    ref.invalidate(kraTemplatesProvider);
    return cloned;
  }
}

final kraTemplateActionsProvider =
    Provider<KraTemplateActions>((ref) => KraTemplateActions(ref));
