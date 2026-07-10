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
      // The list payload carries the item COUNT (`_count.items`) but
      // not the items themselves. We used to hydrate every template's
      // detail in parallel here so the cards could show the weightage
      // pill, but that was N+1 — 30 templates meant 31 round-trips.
      //
      // The card's `KraTemplate.hasWeightageData` already gates the
      // pill on whether items are loaded; without hydration it just
      // hides cleanly, leaving the count visible. Pill becomes visible
      // when the user taps in and the detail screen loads via getById.
      return unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(KraTemplate.fromJson)
          .toList();
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
  Future<void> delete(String id, {bool force = false}) async {
    try {
      await _dio.delete(
        '${ApiConstants.kraTemplates}/$id',
        queryParameters: {if (force) 'force': true},
      );
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
