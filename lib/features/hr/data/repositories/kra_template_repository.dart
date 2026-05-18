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
  Future<void> delete(String id);

  /// Server-side clone — returns the new template with a fresh id.
  /// Cheaper and safer than rebuilding the payload client-side.
  Future<KraTemplate> clone(String id);
}
