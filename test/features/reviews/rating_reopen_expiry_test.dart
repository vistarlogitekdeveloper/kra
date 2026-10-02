import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_reopen.dart';

/// The client-side July/August grant ends exactly when the server's pre-open of
/// the same months does (migration 169: 31 Oct 2026, end of day IST).
///
/// It only applies on a backend that predates rating access, but there it is
/// the only thing keeping those months open — so it must close on the same
/// instant, not run on indefinitely.
void main() {
  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);

  setUp(() => RatingReopen.adopt(RatingReopen.granted));
  tearDown(RatingReopen.reset);

  test('ends on the last instant of 31 Oct 2026 IST', () {
    expect(
        RatingReopen.grantEndsAt, DateTime.utc(2026, 10, 31, 18, 29, 59, 999));
  });

  test('still open on the last instant', () {
    final last = DateTime.utc(2026, 10, 31, 18, 29, 59, 999);
    expect(RatingReopen.allowsBackfill(july, last), isTrue);
    expect(RatingReopen.allowsBackfill(august, last), isTrue);
  });

  test('closed from 1 Nov 2026 00:00 IST', () {
    final midnight = DateTime.utc(2026, 10, 31, 18, 30);
    expect(RatingReopen.allowsBackfill(july, midnight), isFalse);
    expect(RatingReopen.allowsBackfill(august, midnight), isFalse);
    expect(
        RatingReopen.allowsBackfill(july, DateTime.utc(2027, 1, 5)), isFalse);
  });

  test('unchanged before the end: open once the month has ended', () {
    expect(
        RatingReopen.allowsBackfill(july, DateTime.utc(2026, 10, 2)), isTrue);
  });
}
