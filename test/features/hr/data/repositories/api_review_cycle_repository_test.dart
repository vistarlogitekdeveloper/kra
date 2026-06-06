import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/repositories/api_review_cycle_repository.dart';

/// Pins the wire contract for POST /review-cycles. The backend's Zod schema
/// makes `fyLabel`, `quarterNum` and all four stage deadlines REQUIRED, even
/// though the early API spec called them optional. The repository derives
/// the first two from `startDate` (Indian FY: Apr→Mar) and fills any missing
/// deadline from `endDate` so the form's "Optional" affordance still holds.
void main() {
  group('ApiReviewCycleRepository.create wire payload', () {
    late _CapturingAdapter adapter;
    late ApiReviewCycleRepository repo;

    setUp(() {
      adapter = _CapturingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      repo = ApiReviewCycleRepository(dio: dio);
    });

    test('derives fyLabel from a startDate in April (FY start month)', () async {
      await _safeCreate(repo, start: DateTime.utc(2026, 4, 1));
      expect(adapter.lastBody?['fyLabel'], 'FY26-27');
      expect(adapter.lastBody?['quarterNum'], 1);
    });

    test('derives fyLabel for a March startDate (still prior FY)', () async {
      await _safeCreate(repo, start: DateTime.utc(2027, 3, 15));
      expect(adapter.lastBody?['fyLabel'], 'FY26-27');
      expect(adapter.lastBody?['quarterNum'], 4);
    });

    test('quarter mapping: Apr–Jun=1, Jul–Sep=2, Oct–Dec=3, Jan–Mar=4',
        () async {
      final samples = {
        DateTime.utc(2026, 4, 1): 1,
        DateTime.utc(2026, 6, 30): 1,
        DateTime.utc(2026, 7, 1): 2,
        DateTime.utc(2026, 9, 30): 2,
        DateTime.utc(2026, 10, 1): 3,
        DateTime.utc(2026, 12, 31): 3,
        DateTime.utc(2027, 1, 1): 4,
        DateTime.utc(2027, 3, 31): 4,
      };
      for (final entry in samples.entries) {
        await _safeCreate(repo, start: entry.key);
        expect(adapter.lastBody?['quarterNum'], entry.value,
            reason: 'date ${entry.key} should map to Q${entry.value}');
      }
    });

    test('fills missing deadlines from endDate (+15/+31/+46/+62 days)',
        () async {
      final end = DateTime.utc(2026, 6, 30);
      await _safeCreate(
        repo,
        start: DateTime.utc(2026, 4, 1),
        end: end,
      );
      final body = adapter.lastBody!;
      expect(body['selfRatingDeadline'],
          end.add(const Duration(days: 15)).toIso8601String());
      expect(body['managerReviewDeadline'],
          end.add(const Duration(days: 31)).toIso8601String());
      expect(body['opsScoringDeadline'],
          end.add(const Duration(days: 46)).toIso8601String());
      expect(body['financeScoringDeadline'],
          end.add(const Duration(days: 62)).toIso8601String());
    });

    test('keeps caller-supplied deadlines verbatim and does not overwrite them',
        () async {
      final self = DateTime.utc(2026, 7, 5);
      final mgr = DateTime.utc(2026, 7, 10);
      await _safeCreate(
        repo,
        start: DateTime.utc(2026, 4, 1),
        end: DateTime.utc(2026, 6, 30),
        self: self,
        mgr: mgr,
      );
      final body = adapter.lastBody!;
      expect(body['selfRatingDeadline'], self.toIso8601String());
      expect(body['managerReviewDeadline'], mgr.toIso8601String());
      // The two we didn't pass still get backfilled from endDate.
      expect(body['opsScoringDeadline'], isNotNull);
      expect(body['financeScoringDeadline'], isNotNull);
    });
  });
}

Future<void> _safeCreate(
  ApiReviewCycleRepository repo, {
  required DateTime start,
  DateTime? end,
  DateTime? self,
  DateTime? mgr,
}) async {
  // We don't care about the response — the adapter throws after capturing
  // the request, which the repository surfaces as ApiError. Swallow it.
  try {
    await repo.create(
      name: 'probe',
      startDate: start,
      endDate: end ?? start.add(const Duration(days: 90)),
      selfRatingDeadline: self,
      managerReviewDeadline: mgr,
    );
  } catch (_) {/* expected — _CapturingAdapter short-circuits */}
}

/// Captures the most recent outbound request and returns a 500 so the call
/// resolves without us needing to mock a full envelope.
class _CapturingAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final data = options.data;
    if (data is Map<String, dynamic>) lastBody = data;
    return ResponseBody.fromString(
      '{"success": false, "error": {"code": "TEST", "message": "captured"}}',
      500,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
