import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../models/project_location.dart';
import '../../../../core/api/envelope.dart';

abstract class ProjectLocationsRepository {
  /// Active locations only — used by employee/assignment dropdowns.
  Future<List<ProjectLocation>> listActive();

  /// Every location (active or not) — used by the HR management screen.
  Future<List<ProjectLocation>> listAll();

  Future<ProjectLocation> create({
    required String name,
    String? code,
    String? city,
    String? state,
    String? address,
    String? customer,
  });

  Future<ProjectLocation> update(String id, Map<String, dynamic> changes);

  Future<void> delete(String id);
}

class ApiProjectLocationsRepository implements ProjectLocationsRepository {
  final Dio _dio;
  ApiProjectLocationsRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<ProjectLocation>> listActive() async {
    try {
      final response = await _dio.get(
        ApiConstants.locations,
        queryParameters: {'status': 'active', 'limit': 200},
      );
      final raw = unwrapList(response);
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ProjectLocation.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<List<ProjectLocation>> listAll() async {
    try {
      final response = await _dio.get(
        ApiConstants.locations,
        queryParameters: {'limit': 200},
      );
      final raw = unwrapList(response);
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ProjectLocation.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ProjectLocation> create({
    required String name,
    String? code,
    String? city,
    String? state,
    String? address,
    String? customer,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.locations,
        data: {
          'name': name,
          if (code != null && code.isNotEmpty) 'code': code,
          if (city != null && city.isNotEmpty) 'city': city,
          if (state != null && state.isNotEmpty) 'state': state,
          if (address != null && address.isNotEmpty) 'address': address,
          if (customer != null && customer.isNotEmpty) 'customer': customer,
        },
      );
      return ProjectLocation.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<ProjectLocation> update(String id, Map<String, dynamic> changes) async {
    try {
      final response = await _dio.patch(
        '${ApiConstants.locations}/$id',
        data: changes,
      );
      return ProjectLocation.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _dio.delete('${ApiConstants.locations}/$id');
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
