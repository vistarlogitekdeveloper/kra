import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_access.dart';
import 'package:vistar_app/features/reviews/data/models/rating_window.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

/// The super admin's month view (docs/RATING_ACCESS.md §3.5).
///
/// Its only job is to agree with the server: read exactly what was sent, never
/// file an override under the wrong stage, and never invent a month — the
/// screen writes back to whatever month and stage this model names.
void main() {
  const opensAt = '2026-08-31T18:30:00.000Z';
  const selfDeadline = '2026-09-10T18:29:59.999Z';
  const seedEnd = '2026-10-31T18:29:59.999Z';

  Map<String, dynamic> window({
    String source = 'DEADLINE',
    bool closed = false,
    String? closesAt = selfDeadline,
    String deadlineAt = selfDeadline,
  }) =>
      {
        'source': source,
        'closed': closed,
        'opensAt': opensAt,
        'closesAt': closesAt,
        'deadlineAt': deadlineAt,
      };

  Map<String, dynamic> stage(String name,
          {Map<String, dynamic>? win, Map<String, dynamic>? override}) =>
      {
        'stage': name,
        'window': win ?? window(),
        if (override != null) 'override': override,
      };

  Map<String, dynamic> month(List<Map<String, dynamic>> stages,
          {String? flow = 'STANDARD', Object? period = '2026-08'}) =>
      {
        'organizationId': 'org-1',
        'organizationName': 'Vistar Logitek',
        if (flow != null) 'reviewFlow': flow,
        'period': period,
        'stages': stages,
      };

  final seedOverride = {
    'id': 'ovr-1',
    'stage': 'SELF_RATING',
    'period': '2026-08',
    'mode': 'OPEN',
    'openUntil': seedEnd,
    'reason': '  Pre-opened at rollout: pending July/August ratings  ',
    'updatedAt': '2026-10-01T04:30:00.000Z',
    'updatedById': 'sa-1',
    'updatedByName': 'Super Admin',
  };

  group('RatingAccessMode.fromApi', () {
    test('reads the two wire names and nothing else', () {
      expect(RatingAccessMode.fromApi('OPEN'), RatingAccessMode.open);
      expect(RatingAccessMode.fromApi('CLOSED'), RatingAccessMode.closed);
      expect(RatingAccessMode.fromApi(' open '), RatingAccessMode.open);
      expect(RatingAccessMode.fromApi('REOPENED'), isNull);
      expect(RatingAccessMode.fromApi(null), isNull);
    });

    test('round-trips', () {
      for (final mode in RatingAccessMode.values) {
        expect(RatingAccessMode.fromApi(mode.toApiString()), mode);
      }
    });
  });

  group('ratingStageFromWire', () {
    test('reads the five rating stages by exact wire name', () {
      for (final stage in ReviewStage.values.where((s) => s.isRatingStage)) {
        expect(ratingStageFromWire(stage.toApiString()), stage);
      }
    });

    test('an alias or unknown name is null, never Self-rating', () {
      // ReviewStage.fromApi accepts HR_RATING and files unknowns under
      // SELF_RATING; either would put an override on the wrong seat here.
      expect(ReviewStage.fromApi('OPS_EXCELLENCE_SCORING'),
          ReviewStage.selfRating);
      expect(ratingStageFromWire('OPS_EXCELLENCE_SCORING'), isNull);
      expect(ratingStageFromWire('HR_RATING'), isNull);
      expect(ratingStageFromWire(null), isNull);
    });

    test('payout and completed are not ratings', () {
      expect(ratingStageFromWire('INCENTIVE_PAYOUT'), isNull);
      expect(ratingStageFromWire('COMPLETED'), isNull);
    });
  });

  group('parseRatingPeriod', () {
    test('reads YYYY-MM', () {
      expect(parseRatingPeriod('2026-08'), const ReviewPeriod(2026, 8));
      expect(parseRatingPeriod(' 2026-12 '), const ReviewPeriod(2026, 12));
    });

    test('rejects garbage instead of inventing a month', () {
      // The lenient parser turns garbage into a real-looking month.
      expect(ReviewPeriod.parse('garbage'), const ReviewPeriod(0, 1));
      for (final bad in [
        'garbage',
        '',
        '2026-8',
        '2026-13',
        '2026-00',
        '1999-12',
        '2101-01',
        '2026-08-01',
        '20260-08',
      ]) {
        expect(parseRatingPeriod(bad), isNull, reason: bad);
      }
      expect(parseRatingPeriod(null), isNull);
    });
  });

  group('RatingAccessMonth.fromJson', () {
    test('reads the contract payload', () {
      final parsed = RatingAccessMonth.fromJson(month([
        stage('SELF_RATING',
            win: window(source: 'OPENED', closesAt: seedEnd),
            override: seedOverride),
        stage('REPORTING_MANAGER_RATING'),
        stage('ACCOUNT_HR_RATING',
            win: window(source: 'CLOSED', closed: true, closesAt: null)),
        stage('FINANCE_RATING'),
        stage('MANAGEMENT_REVIEW'),
      ]));

      expect(parsed, isNotNull);
      final m = parsed as RatingAccessMonth;
      expect(m.organizationId, 'org-1');
      expect(m.organizationName, 'Vistar Logitek');
      expect(m.reviewFlow, ReviewFlow.standard);
      expect(m.period, const ReviewPeriod(2026, 8));
      expect([
        for (final s in m.stages) s.stage
      ], [
        ReviewStage.selfRating,
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
        ReviewStage.managementReview,
      ]);

      final self = m.stageFor(ReviewStage.selfRating);
      expect(self?.window.source, RatingWindowSource.opened);
      expect(self?.window.closesAt, DateTime.parse(seedEnd));
      final o = self?.adminOverride;
      expect(o?.id, 'ovr-1');
      expect(o?.mode, RatingAccessMode.open);
      expect(o?.period, const ReviewPeriod(2026, 8));
      expect(o?.openUntil, DateTime.parse(seedEnd));
      expect(o?.reason, 'Pre-opened at rollout: pending July/August ratings',
          reason: 'trimmed');
      expect(o?.updatedAt, DateTime.parse('2026-10-01T04:30:00.000Z'));
      expect(o?.updatedById, 'sa-1');
      expect(o?.updatedByName, 'Super Admin');

      expect(m.stageFor(ReviewStage.accountHrRating)?.window.closed, isTrue);
      expect(m.stageFor(ReviewStage.reportingManagerRating)?.adminOverride,
          isNull);
    });

    test('an unknown or aliased stage is skipped, not filed as Self', () {
      final m = RatingAccessMonth.fromJson(month([
        stage('OPS_EXCELLENCE_SCORING'),
        stage('HR_RATING'),
        stage('INCENTIVE_PAYOUT'),
        stage('FINANCE_RATING'),
      ]));
      expect([for (final s in m?.stages ?? <RatingAccessStage>[]) s.stage],
          [ReviewStage.financeRating]);
    });

    test('a window without opensAt is skipped', () {
      final m = RatingAccessMonth.fromJson(month([
        stage('SELF_RATING', win: {'source': 'OPENED', 'closed': false}),
        {'stage': 'REPORTING_MANAGER_RATING', 'window': 'not-a-map'},
        stage('FINANCE_RATING'),
      ]));
      expect([for (final s in m?.stages ?? <RatingAccessStage>[]) s.stage],
          [ReviewStage.financeRating]);
    });

    test('stages come back in pipeline order, first duplicate wins', () {
      final m = RatingAccessMonth.fromJson(month([
        stage('MANAGEMENT_REVIEW'),
        stage('SELF_RATING'),
        stage('SELF_RATING', win: window(source: 'CLOSED', closed: true)),
      ]));
      expect([for (final s in m?.stages ?? <RatingAccessStage>[]) s.stage],
          [ReviewStage.selfRating, ReviewStage.managementReview]);
      expect(m?.stageFor(ReviewStage.selfRating)?.window.closed, isFalse);
    });

    test('an override filed under another stage, or with no mode, is dropped',
        () {
      final m = RatingAccessMonth.fromJson(month([
        stage('REPORTING_MANAGER_RATING', override: seedOverride),
        stage('FINANCE_RATING', override: {
          ...seedOverride,
          'stage': 'FINANCE_RATING',
          'mode': 'MAYBE',
        }),
      ]));
      expect(m?.stageFor(ReviewStage.reportingManagerRating)?.adminOverride,
          isNull);
      expect(m?.stageFor(ReviewStage.financeRating)?.adminOverride, isNull);
      expect(m?.stages, hasLength(2), reason: 'the stages themselves stay');
    });

    test('an embedded override without a period takes the month', () {
      final m = RatingAccessMonth.fromJson(month([
        stage('SELF_RATING', override: {...seedOverride}..remove('period')),
      ]));
      expect(m?.stageFor(ReviewStage.selfRating)?.adminOverride?.period,
          const ReviewPeriod(2026, 8));
    });

    test('a garbage period falls back to the month asked for, or fails', () {
      final raw = month([stage('SELF_RATING')], period: 'garbage');
      expect(RatingAccessMonth.fromJson(raw), isNull);
      expect(
        RatingAccessMonth.fromJson(raw,
                fallbackPeriod: const ReviewPeriod(2026, 7))
            ?.period,
        const ReviewPeriod(2026, 7),
      );
    });

    test('year and month parts are read when period is absent', () {
      final raw = month([stage('SELF_RATING')], period: null)
        ..['year'] = 2026
        ..['month'] = '9';
      expect(
          RatingAccessMonth.fromJson(raw)?.period, const ReviewPeriod(2026, 9));
    });

    test('nothing parsable is a malformed answer, not an empty month', () {
      expect(RatingAccessMonth.fromJson(month([stage('BOGUS')])), isNull);
      expect(RatingAccessMonth.fromJson(month([])), isNull);
      expect(RatingAccessMonth.fromJson('not-a-map'), isNull);
      expect(RatingAccessMonth.fromJson(null), isNull);
    });

    test('identity falls back sensibly', () {
      final m = RatingAccessMonth.fromJson(
        {
          'organizationName': '  ',
          'period': '2026-08',
          'stages': [stage('SELF_RATING')],
        },
        fallbackOrganizationId: 'org-from-path',
      );
      expect(m?.organizationId, 'org-from-path');
      expect(m?.organizationName, isNull);
      expect(m?.reviewFlow, ReviewFlow.standard,
          reason: 'an absent flow is the original pipeline');
    });

    test('ADMIN_ONLY has no self-rating stage in its flow', () {
      final stages = [
        stage('SELF_RATING', override: seedOverride),
        stage('REPORTING_MANAGER_RATING'),
        stage('MANAGEMENT_REVIEW'),
      ];
      final m = RatingAccessMonth.fromJson(month(stages, flow: 'ADMIN_ONLY'));
      expect(
          [for (final s in m?.stagesInFlow ?? <RatingAccessStage>[]) s.stage],
          [ReviewStage.reportingManagerRating, ReviewStage.managementReview]);
      // The rollout seeds the self-rating for every organisation; it is not a
      // stage this flow uses, so it does not count as an override in flow.
      expect(m?.hasOverrideInFlow, isFalse);
      expect(
          RatingAccessMonth.fromJson(month(stages))?.hasOverrideInFlow, isTrue);
    });
  });

  group('RatingAccessOverride.fromJson', () {
    test('a CLOSED override never carries an end', () {
      final o =
          RatingAccessOverride.fromJson({...seedOverride, 'mode': 'CLOSED'});
      expect(o?.mode, RatingAccessMode.closed);
      expect(o?.openUntil, isNull);
    });

    test('a blank reason reads as none', () {
      expect(
          RatingAccessOverride.fromJson({...seedOverride, 'reason': '   '})
              ?.reason,
          isNull);
    });

    test('needs a stage, a mode and a month', () {
      expect(RatingAccessOverride.fromJson({...seedOverride}..remove('stage')),
          isNull);
      expect(RatingAccessOverride.fromJson({...seedOverride}..remove('mode')),
          isNull);
      expect(
          RatingAccessOverride.fromJson({...seedOverride, 'period': 'garbage'}),
          isNull);
      expect(RatingAccessOverride.fromJson('nope'), isNull);
    });

    test('an OPEN override has ended once its end has passed', () {
      final o = RatingAccessOverride.fromJson(seedOverride);
      final end = DateTime.parse(seedEnd);
      expect(o?.hasEndedAt(end), isFalse);
      expect(o?.hasEndedAt(end.add(const Duration(milliseconds: 1))), isTrue);
      final noEnd =
          RatingAccessOverride.fromJson({...seedOverride, 'openUntil': null});
      expect(noEnd?.hasEndedAt(DateTime.utc(2030)), isFalse);
    });

    test('newestFirst sorts by updatedAt, unknown last', () {
      RatingAccessOverride at(String id, String? updatedAt) =>
          RatingAccessOverride(
            id: id,
            stage: ReviewStage.selfRating,
            period: const ReviewPeriod(2026, 8),
            mode: RatingAccessMode.closed,
            updatedAt: updatedAt == null ? null : DateTime.parse(updatedAt),
          );
      final sorted = [
        at('old', '2026-09-01T00:00:00Z'),
        at('none', null),
        at('new', '2026-10-01T00:00:00Z'),
      ]..sort(RatingAccessOverride.newestFirst);
      expect([for (final o in sorted) o.id], ['new', 'old', 'none']);
    });
  });

  group('RatingAccessStage.overrideIsInert', () {
    RatingAccessStage entry(String source, String? mode) {
      final parsed = RatingAccessStage.fromJson(stage(
        'SELF_RATING',
        win: window(source: source),
        override: mode == null ? null : {...seedOverride, 'mode': mode},
      ));
      return parsed ?? (throw StateError('fixture did not parse'));
    }

    test('an OPEN override the server resolved to the deadline changed nothing',
        () {
      expect(entry('DEADLINE', 'OPEN').overrideIsInert, isTrue);
      expect(entry('OPENED', 'OPEN').overrideIsInert, isFalse);
      expect(entry('CLOSED', 'CLOSED').overrideIsInert, isFalse);
      expect(entry('DEADLINE', null).overrideIsInert, isFalse);
    });
  });
}
