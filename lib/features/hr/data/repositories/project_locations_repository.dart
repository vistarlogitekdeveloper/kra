import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../models/project_location.dart';
import '../../../../core/api/envelope.dart';

abstract class ProjectLocationsRepository {
  Future<List<ProjectLocation>> listActive();
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
}
