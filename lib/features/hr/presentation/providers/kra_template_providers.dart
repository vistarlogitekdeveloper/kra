import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../data/models/kra_template.dart';
import '../../data/repositories/api_kra_template_repository.dart';
import '../../data/repositories/kra_template_repository.dart';

/// Outcome of a bulk "delete all templates" run. Some templates may be
/// undeletable (the backend RESTRICTs deleting a template whose KRA items
/// are still referenced by existing review rows) — those land in [failed].
class BulkTemplateDeleteResult {
  final int deleted;
  final List<({String name, String reason})> failed;
  const BulkTemplateDeleteResult({required this.deleted, required this.failed});

  int get total => deleted + failed.length;
  bool get allDeleted => failed.isEmpty;
}

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
    // PATCH /kra-templates/:id rejects `description: null` with
    // `VAL_001 "Invalid input: expected string, received null"` — the
    // backend Zod schema makes description nullable on the model but
    // the PATCH validator only accepts a string. Empty string is fine
    // (and gives the user a real way to clear an existing description
    // by emptying the field). Coerce null → '' so the request is always
    // well-formed regardless of what the form holds.
    final updated = await _repo.update(id, {
      'name': template.name,
      'role': template.role,
      'description': template.description ?? '',
      'items': template.items.map((e) => e.toJson()).toList(),
    });
    ref.invalidate(kraTemplatesProvider);
    ref.invalidate(kraTemplateDetailProvider(id));
    return updated;
  }

  /// Deletes a template. On 409 (referenced by reviews) the caller can
  /// retry with [force] to archive it instead.
  Future<void> delete(String id, {bool force = false}) async {
    await _repo.delete(id, force: force);
    ref.invalidate(kraTemplatesProvider);
  }

  /// Deletes **every** KRA template — including the system-default ones
  /// ("irrespective of the default KRA"). Attempts each independently so a
  /// single undeletable template doesn't abort the rest; the outcome
  /// reports how many went and which were skipped and why.
  ///
  /// The backend enforces a `RESTRICT` foreign key from `review_rows` to
  /// `kra_template_items`, so a template whose KRAs are already used by an
  /// existing review can't be removed until those reviews are gone. That's
  /// a database-level rule we can't override from the client — such
  /// templates are surfaced in [BulkTemplateDeleteResult.failed].
  Future<BulkTemplateDeleteResult> deleteAll() async {
    // isActive: null → every template, active or not, all roles.
    final templates = await _repo.list(isActive: null);
    var deleted = 0;
    final failed = <({String name, String reason})>[];
    for (final t in templates) {
      try {
        await _repo.delete(t.id);
        deleted++;
      } on ApiError catch (e) {
        failed.add((name: t.name, reason: _deleteFailureReason(e)));
      } catch (_) {
        failed.add((name: t.name, reason: 'Unexpected error'));
      }
    }
    ref.invalidate(kraTemplatesProvider);
    return BulkTemplateDeleteResult(deleted: deleted, failed: failed);
  }

  String _deleteFailureReason(ApiError e) {
    final msg = e.message.toLowerCase();
    if (e.statusCode == 409 ||
        msg.contains('in use') ||
        msg.contains('review_rows') ||
        msg.contains('foreign key') ||
        msg.contains('constraint') ||
        (e.statusCode == 500 && msg.contains('delete'))) {
      return 'In use by existing reviews (archive it individually)';
    }
    if (msg.contains('default')) return 'Protected default template';
    return e.message;
  }

  Future<KraTemplate> clone(String id) async {
    final cloned = await _repo.clone(id);
    ref.invalidate(kraTemplatesProvider);
    return cloned;
  }
}

final kraTemplateActionsProvider =
    Provider<KraTemplateActions>((ref) => KraTemplateActions(ref));
