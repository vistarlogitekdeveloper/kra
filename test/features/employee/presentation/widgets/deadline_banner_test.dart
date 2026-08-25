import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/presentation/screens/home/widgets/deadline_banner.dart';

/// Guards the banner's wording.
///
/// Reported as "self rating is done, still it is showing that self rating is
/// overdue". Two separate causes, both wording:
///   1. the banner never said WHICH month was overdue, and the self-rate sheet
///      shows a whole quarter — so rating the quarter's first month and then
///      being told "Self-rating overdue" read as a bug;
///   2. an employee whose scores were typed in but never submitted was told
///      only "overdue", which reads as the app having lost the work.
void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('overdue names the month', (tester) async {
    await tester.pumpWidget(host(const DeadlineBanner(
      daysRemaining: -15,
      isOverdue: true,
      monthLabel: "Aug '26",
    )));

    expect(find.text("Aug '26 self-rating is overdue — submit now"),
        findsOneWidget);
  });

  testWidgets('scores entered but not submitted says so, not just "overdue"',
      (tester) async {
    await tester.pumpWidget(host(const DeadlineBanner(
      daysRemaining: -15,
      isOverdue: true,
      monthLabel: "Aug '26",
      ratedButNotSubmitted: true,
    )));

    expect(
      find.text("Aug '26 self-rating is filled in but not submitted — "
          'tap to submit'),
      findsOneWidget,
    );
    expect(find.textContaining('overdue'), findsNothing);
  });

  testWidgets('the countdown names the month too, and pluralises the unit',
      (tester) async {
    await tester.pumpWidget(host(const DeadlineBanner(
      daysRemaining: 2,
      isOverdue: false,
      monthLabel: "Aug '26",
    )));
    expect(find.text("Aug '26 self-rating closes in 2 days"), findsOneWidget);

    await tester.pumpWidget(host(const DeadlineBanner(
      daysRemaining: 1,
      isOverdue: false,
      monthLabel: "Aug '26",
    )));
    expect(find.text("Aug '26 self-rating closes in 1 day"), findsOneWidget);
  });

  testWidgets('no month to name → the original wording, never a dangling label',
      (tester) async {
    await tester.pumpWidget(host(const DeadlineBanner(
      daysRemaining: -3,
      isOverdue: true,
    )));
    expect(find.text('Self-rating overdue — submit now'), findsOneWidget);

    await tester.pumpWidget(host(const DeadlineBanner(
      daysRemaining: 3,
      isOverdue: false,
    )));
    expect(find.text('Self-rating closes in 3 days'), findsOneWidget);
  });
}
