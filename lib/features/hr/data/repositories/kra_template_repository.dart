import '../models/kra_template.dart';
import '../models/kra_template_item.dart';

abstract class KraTemplateRepository {
  Future<List<KraTemplate>> list({String? role, bool? isActive});
  Future<KraTemplate> getById(String id);
  Future<KraTemplate> create({
    required String name,
    required String role,
    String? description,
    required List<KraTemplateItem> items,
  });
  Future<KraTemplate> update(String id, Map<String, dynamic> changes);

  /// Deletes a template. A template referenced by existing reviews cannot
  /// be hard-deleted — the backend returns 409; pass [force] to archive
  /// (soft-delete) it instead, which excludes it from lists/pickers while
  /// preserving history and freeing its name for reuse.
  Future<void> delete(String id, {bool force = false});

  /// Server-side clone — returns the new template with a fresh id.
  /// Cheaper and safer than rebuilding the payload client-side.
  Future<KraTemplate> clone(String id);
}
