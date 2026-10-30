import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/dio_client.dart';
import '../../../../core/api/envelope.dart';
import '../../../hr/data/models/employee.dart';
import '../models/review_stage.dart';

/// The file formats the KRA rating report comes in.
enum RatingReportFormat {
  excel('xlsx', 'Excel'),
  pdf('pdf', 'PDF');

  const RatingReportFormat(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// The ratings a report can carry, in pipeline order.
const ratingReportStages = <ReviewStage>[
  ReviewStage.selfRating,
  ReviewStage.reportingManagerRating,
  ReviewStage.accountHrRating,
  ReviewStage.financeRating,
  ReviewStage.managementReview,
];

/// What to put in the report. [employeeIds] null = every active employee.
class RatingReportRequest {
  final List<DateTime> months;
  final List<String>? employeeIds;
  final Set<ReviewStage> stages;
  final RatingReportFormat format;

  const RatingReportRequest({
    required this.months,
    required this.employeeIds,
    required this.stages,
    required this.format,
  });

  Map<String, dynamic> toJson() => {
        'months': ([...months]..sort())
            .map((m) => '${m.year}-${m.month.toString().padLeft(2, '0')}')
            .toList(),
        if (employeeIds != null) 'employeeIds': employeeIds,
        'stages': [
          for (final s in ratingReportStages)
            if (stages.contains(s)) s.toApiString(),
        ],
        'format': format.apiValue,
      };
}

/// The generated file, decoded and ready to save.
class RatingReportFile {
  final String fileName;
  final String mime;
  final Uint8List bytes;
  final int reviews;
  final int employees;

  const RatingReportFile({
    required this.fileName,
    required this.mime,
    required this.bytes,
    required this.reviews,
    required this.employees,
  });
}

/// `POST /reviews/monthly/report`. The server builds the Excel / PDF (the
/// same rules as the quarterly sheet) and returns it base64 in the normal
/// envelope, like the proof download, so the auth interceptor applies.
class RatingReportRepository {
  final Dio _dio;
  RatingReportRepository(this._dio);

  Future<RatingReportFile> download(RatingReportRequest request) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.monthlyReviews}/report',
        data: request.toJson(),
        // A whole organisation over a year is a big PDF to build; the
        // default 60 s would cut it off.
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
      final json = unwrapObject(response);
      return RatingReportFile(
        fileName: (json['fileName'] as String?) ?? 'KRA_ratings',
        mime: (json['mime'] as String?) ?? 'application/octet-stream',
        bytes: base64Decode((json['data'] as String?) ?? ''),
        reviews: (json['reviews'] as num?)?.toInt() ?? 0,
        employees: (json['employees'] as num?)?.toInt() ?? 0,
      );
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}

final ratingReportRepositoryProvider = Provider<RatingReportRepository>(
  (ref) => RatingReportRepository(ref.watch(dioProvider)),
);

/// Every employee of the organisation for the report's picker, A to Z.
/// The list endpoint pages at most 200 at a time, so this walks the pages.
/// `true` also includes deactivated employees (their history is reportable):
/// that needs `status=all` — leaving `isActive` out still means active only.
final ratingReportEmployeesProvider =
    FutureProvider.autoDispose.family<List<Employee>, bool>(
  (ref, includeInactive) async {
    final dio = ref.watch(dioProvider);
    final all = <Employee>[];
    try {
      for (var page = 1; page <= 100; page++) {
        final response = await dio.get(
          ApiConstants.employees,
          queryParameters: {
            'page': page,
            'limit': 200,
            'status': includeInactive ? 'all' : 'active',
          },
        );
        final result = EmployeePage.fromJson(unwrapPaged(response));
        all.addAll(result.employees);
        if (!result.hasMore || result.employees.isEmpty) break;
      }
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
    all.sort((a, b) =>
        a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return all;
  },
);
