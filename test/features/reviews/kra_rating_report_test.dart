import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/models/employee.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/repositories/rating_report_repository.dart';
import 'package:vistar_app/features/reviews/presentation/screens/kra_rating_report_screen.dart';

/// KRA rating report: HR / Accounts / management choose employees (all, some,
/// one), months and ratings (all by default) and download Excel or PDF.
class _FakeRepo extends RatingReportRepository {
  _FakeRepo() : super(Dio());
  final requests = <RatingReportRequest>[];

  @override
  Future<RatingReportFile> download(RatingReportRequest request) async {
    requests.add(request);
    return RatingReportFile(
      fileName: 'KRA_ratings.xlsx',
      mime: 'application/octet-stream',
      bytes: Uint8List.fromList([1, 2, 3]),
      reviews: 3,
      employees: 2,
    );
  }
}

Employee _emp(String id, String name, {bool active = true}) => Employee(
      id: id,
      employeeCode: 'VLPL$id',
      fullName: name,
      email: '$id@x.com',
      role: 'EMPLOYEE',
      isActive: active,
    );

void main() {
  group('the request', () {
    test('months sorted as YYYY-MM, ratings in pipeline order, all = no ids', () {
      final json = RatingReportRequest(
        months: [DateTime(2026, 9), DateTime(2026, 7)],
        employeeIds: null,
        stages: {ReviewStage.managementReview, ReviewStage.selfRating},
        format: RatingReportFormat.pdf,
      ).toJson();
      expect(json['months'], ['2026-07', '2026-09']);
      expect(json['stages'], ['SELF_RATING', 'MANAGEMENT_REVIEW']);
      expect(json.containsKey('employeeIds'), isFalse);
      expect(json['format'], 'pdf');
    });

    test('chosen employees are sent', () {
      final json = RatingReportRequest(
        months: [DateTime(2026, 9)],
        employeeIds: const ['a', 'b'],
        stages: {...ratingReportStages},
        format: RatingReportFormat.excel,
      ).toJson();
      expect(json['employeeIds'], ['a', 'b']);
      expect(json['format'], 'xlsx');
      expect(json['stages'], hasLength(5));
    });
  });

  group('the screen', () {
    late _FakeRepo repo;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo = _FakeRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ratingReportRepositoryProvider.overrideWithValue(repo),
          ratingReportEmployeesProvider.overrideWith((ref, includeInactive) async => [
                _emp('1', 'Kisan Bhosale'),
                _emp('2', 'Ganga Jha'),
                if (includeInactive) _emp('3', 'Left Company', active: false),
              ]),
        ],
        child: const MaterialApp(home: KraRatingReportScreen()),
      ));
      await tester.pumpAndSettle();
    }

    Finder download() => find.byKey(const Key('ratingReportDownload'));

    testWidgets('defaults: all employees, last month, every rating, Excel',
        (tester) async {
      await pump(tester);
      final now = DateTime.now();
      final last = DateTime(now.year, now.month - 1);
      await tester.tap(download());
      await tester.pumpAndSettle();
      expect(repo.requests, hasLength(1));
      final r = repo.requests.single;
      expect(r.employeeIds, isNull);
      expect(r.months, [last]);
      expect(r.stages, ratingReportStages.toSet());
      expect(r.format, RatingReportFormat.excel);
    });

    testWidgets('no rating chosen blocks the download, with the reason',
        (tester) async {
      await pump(tester);
      for (final label in ['Self rating', 'Manager rating', 'HR rating', 'Accounts rating', 'Management rating']) {
        await tester.tap(find.text(label));
      }
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(download()).onPressed, isNull);
      expect(find.text('Choose at least one rating.'), findsOneWidget);
      await tester.tap(find.text('Select all ratings'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(download()).onPressed, isNotNull);
    });

    testWidgets('choose employees: none blocks; picked ones are sent; PDF',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Choose employees'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(download()).onPressed, isNull);
      expect(find.text('Choose at least one employee, or switch to All employees.'), findsOneWidget);

      await tester.tap(find.text('Ganga Jha'));
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(download());
      await tester.pumpAndSettle();
      expect(repo.requests.single.employeeIds, ['2']);
      expect(repo.requests.single.format, RatingReportFormat.pdf);
    });

    testWidgets('search narrows the list; deactivated only when asked',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Choose employees'));
      await tester.pumpAndSettle();
      expect(find.text('Left Company'), findsNothing);
      await tester.tap(find.text('Include deactivated'));
      await tester.pumpAndSettle();
      expect(find.text('Left Company'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('ratingReportSearch')), 'VLPL3');
      await tester.pumpAndSettle();
      expect(find.text('Kisan Bhosale'), findsNothing);
      await tester.tap(find.text('Select all shown'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      // Hiding deactivated again drops them from the selection.
      await tester.tap(find.text('Include deactivated'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
    });

    testWidgets('months: clearing blocks; a quarter adds its started months',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Clear').last);
      await tester.pumpAndSettle();
      expect(find.text('No month selected'), findsOneWidget);
      expect(tester.widget<FilledButton>(download()).onPressed, isNull);
      await tester.tap(find.text('Whole year'));
      await tester.pumpAndSettle();
      await tester.tap(download());
      await tester.pumpAndSettle();
      final months = repo.requests.single.months;
      final now = DateTime(DateTime.now().year, DateTime.now().month);
      expect(months, isNotEmpty);
      expect(months.every((m) => !m.isAfter(now)), isTrue, reason: 'no future month');
    });
  });
}
