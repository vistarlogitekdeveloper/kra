import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../models/kra_template.dart';
import '../models/kra_template_item.dart';
import '../../../../core/api/envelope.dart';
import 'kra_template_repository.dart';

class ApiKraTemplateRepository implements KraTemplateRepository {
  final Dio _dio;
  ApiKraTemplateRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<KraTemplate>> list({String? role, bool? isActive}) async {
    try {
      final response = await _dio.get(
        ApiConstants.kraTemplates,
        queryParameters: {
          if (role != null && role.isNotEmpty) 'role': role,
          if (isActive != null) 'isActive': isActive,
        },
      );
      final summaries = unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(KraTemplate.fromJson)
          .toList();
      // The list endpoint returns the item COUNT (`_count.items`) but not
      // the items themselves, so the weightage total can't be derived
      // from it. Hydrate each template's items in parallel so the cards
      // can show an accurate weightage. A per-template failure degrades
      // gracefully to the summary (the count still renders via itemCount).
      return Future.wait(
        summaries.map((t) async {
          try {
            return await getById(t.id);
          } catch (_) {
            return t;
          }
        }),
      );
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<KraTemplate> getById(String id) async {
    try {
      final response = await _dio.get('${ApiConstants.kraTemplates}/$id');
      return KraTemplate.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<KraTemplate> create({
    required String name,
    required String role,
    String? description,
    required List<KraTemplateItem> items,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.kraTemplates,
        data: {
          'name': name,
          'role': role,
          if (description != null) 'description': description,
          'items': items.map((e) => e.toJson()).toList(),
        },
      );
      return KraTemplate.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<KraTemplate> update(String id, Map<String, dynamic> changes) async {
    try {
      final response = await _dio.patch(
        '${ApiConstants.kraTemplates}/$id',
        data: changes,
      );
      return KraTemplate.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _dio.delete('${ApiConstants.kraTemplates}/$id');
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<KraTemplate> clone(String id) async {
    try {
      final response = await _dio.post('${ApiConstants.kraTemplates}/$id/clone');
      return KraTemplate.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
