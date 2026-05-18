import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../models/my_kra_assignment.dart';
import 'my_kra_repository.dart';

class ApiMyKraRepository implements MyKraRepository {
  final Dio _dio;
  ApiMyKraRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<MyKraAssignment>> listMyAssignments({String? cycleId}) async {
    try {
      final response = await _dio.get(
        ApiConstants.employeeKraAssignments,
        queryParameters: {
          if (cycleId != null && cycleId.isNotEmpty) 'cycleId': cycleId,
        },
      );
      final raw = unwrapList(response);
      return raw
          .whereType<Map<String, dynamic>>()
          .map(MyKraAssignment.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
