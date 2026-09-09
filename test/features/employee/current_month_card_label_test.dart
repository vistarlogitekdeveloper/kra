import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/data/models/employee_dashboard.dart';
import 'package:vistar_app/features/employee/data/models/enums.dart';
import 'package:vistar_app/features/employee/presentation/screens/home/widgets/current_month_card.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';

/// The reported bug, reproduced: on 9 September the home card said
/// "Sep-26 / Self-rating pending" when August was what was owed.
///
/// The cause was that this card rendered the API's `currentMonth.monthLabel`
/// verbatim, and the server picks the cycle month matching TODAY. An earlier
/// fix corrected `_periodFor` — which feeds the deadline banner — and the card
/// went on showing September, because it never consulted that value. Two
/// independent display paths, one of them fixed.
///
/// So the card no longer derives a month at all: it is handed one. These tests
/// pin that it renders what it is given and that the server's own label cannot
/// leak through.
void main() {
  const cycle = DashboardCycle(id: 'c1', name: 'FY26-27 Q2', status: 'ACTIVE');

  /// A server payload naming SEPTEMBER — exactly what the API returned.
  const septemberFromServer = DashboardCurrentMonth(
    id: 'm-sep',
    monthLabel: 'Sep-26',
    status: ReviewMonthStatus.open,
  );

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  Widget card({required String monthLabel}) => host(CurrentMonthCard(
        cycle: cycle,
        currentMonth: septemberFromServer,
        scorecard: null,
        monthLabel: monthLabel,
        onPrimaryAction: () {},
      ));

  group('the card renders the month it is GIVEN', () {
    testWidgets('August shows even though the payload says September',
        (tester) async {
      await tester.pumpWidget(card(monthLabel: 'Aug-26'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Aug-26'), findsOneWidget);
      expect(
        find.text('Sep-26'),
        findsNothing,
        reason: 'the API label must not reach the screen — that WAS the bug',
      );
    });

    testWidgets('it still shows the pending state and its action',
        (tester) async {
      // The fix must not have changed what the card is; only which month.
      await tester.pumpWidget(card(monthLabel: 'Aug-26'));
      await tester.pump();

      expect(
          find.textContaining('Self-rating', findRichText: true), findsWidgets);
      expect(find.textContaining('Start rating', findRichText: true),
          findsWidgets);
    });
  });

  group('composed with the clamp, the reported scenario comes out right', () {
    test('server says September, clock is 9 September → the label is Aug-26',
        () {
      // The whole chain the home screen runs, at the logic level: take the
      // server's month, clamp it to what can actually be rated, render that.
      const serverMonth = ReviewPeriod(2026, 9);
      final label =
          serverMonth.clampToRatable(DateTime(2026, 9, 9)).compactLabel;

      expect(label, 'Aug-26');
    });

    test('and on 4 January it is Dec-26, not Jan-27', () {
      // The year boundary, which a hand-rolled "month - 1" gets wrong.
      const serverMonth = ReviewPeriod(2027, 1);
      final label =
          serverMonth.clampToRatable(DateTime(2027, 1, 4)).compactLabel;

      expect(label, 'Dec-26');
    });
  });

  group('the card must not start deriving its own label again', () {
    // Source-level, because this is a SHAPE of mistake rather than one
    // instance: any `?? DateTime.now()` or read of `currentMonth.monthLabel`
    // in here reintroduces a second, disagreeing source of truth. A
    // behavioural test would only catch the specific reintroduction it
    // happened to be written for.
    final source = File(
      'lib/features/employee/presentation/screens/home/widgets/'
      'current_month_card.dart',
    ).readAsStringSync();

    final code = source.split('\n').map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    }).join('\n');

    test('it does not read the API month label', () {
      expect(
        code.contains('monthLabel ??'),
        isFalse,
        reason: 'the card is handed a label; falling back to the payload\'s '
            'reintroduces the September bug',
      );
      expect(code.contains('currentMonth?.monthLabel'), isFalse);
    });

    test('it does not fall back to the device clock', () {
      expect(
        code.contains('DateTime.now()'),
        isFalse,
        reason: 'today\'s month can never be the month under review',
      );
    });
  });
}
