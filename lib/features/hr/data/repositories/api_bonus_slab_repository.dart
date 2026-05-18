import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../models/bonus_slab.dart';
import '../../../../core/api/envelope.dart';
import 'bonus_slab_repository.dart';

class ApiBonusSlabRepository implements BonusSlabRepository {
  final Dio _dio;
  ApiBonusSlabRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<BonusSlab>> listForCycle(String cycleId) async {
    try {
      final response = await _dio.get(
        ApiConstants.bonusSlabs,
        queryParameters: {'cycleId': cycleId},
      );
      return unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(BonusSlab.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<BonusSlab> create({
    required String cycleId,
    required String grade,
    required double monthlyEligibleAmount,
    required double quarterlyEligibleAmount,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.bonusSlabs,
        data: {
          'cycleId': cycleId,
          'grade': grade,
          'monthlyEligibleAmount': monthlyEligibleAmount,
          'quarterlyEligibleAmount': quarterlyEligibleAmount,
        },
      );
      return BonusSlab.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<BonusSlab> update(String id, Map<String, dynamic> changes) async {
    try {
      final response = await _dio.patch(
        '${ApiConstants.bonusSlabs}/$id',
        data: changes,
      );
      return BonusSlab.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
