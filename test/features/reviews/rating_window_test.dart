import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/rating_window.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

/// The client's copy of the server-resolved rating window
/// (docs/RATING_ACCESS.md §2 and §4.1).
///
/// The server enforces the same answer on every write, so the only job of this
/// model is to agree with it: parse exactly what was sent, never invent an
/// opening, and never let a malformed or unknown key open the wrong stage.
void main() {
  // August 2026, Self-rating: opens 1 Sep 00:00 IST, closes 10 Sep 23:59:59.999 IST.
  final opensAt = DateTime.utc(2026, 8, 31, 18, 30);
  final deadlineAt = DateTime.utc(2026, 9, 10, 18, 29, 59, 999);

  RatingWindow window({
    RatingWindowSource source = RatingWindowSource.deadline,
    bool closed = false,
    DateTime? closesAt,
    bool noEnd = false,
  }) =>
      RatingWindow(
        source: source,
        closed: closed,
        opensAt: opensAt,
        closesAt: noEnd ? null : (closesAt ?? deadlineAt),
        deadlineAt: deadlineAt,
      );

  group('isOpenAt', () {
    test('is shut before the month has ended', () {
      expect(
          window().isOpenAt(opensAt.subtract(const Duration(milliseconds: 1))),
          isFalse);
    });

    test('is open from the opening instant itself', () {
      expect(window().isOpenAt(opensAt), isTrue);
    });

    test('is open on the deadline instant and shut one millisecond later', () {
      expect(window().isOpenAt(deadlineAt), isTrue);
      expect(window().isOpenAt(deadlineAt.add(const Duration(milliseconds: 1))),
          isFalse);
    });

    test('compares instants, not wall clocks', () {
      // 11 Sep 00:30 IST is 10 Sep 19:00 UTC — past the deadline whichever
      // zone the device reports it in.
      final lateUtc = DateTime.utc(2026, 9, 10, 19);
      expect(window().isOpenAt(lateUtc), isFalse);
      expect(window().isOpenAt(lateUtc.toLocal()), isFalse);
    });

    test('a window with no end stays open', () {
      final w = window(source: RatingWindowSource.returned, noEnd: true);
      expect(w.isOpenAt(DateTime.utc(2027, 3, 1)), isTrue);
    });

    test('closed beats every instant', () {
      final w =
          window(source: RatingWindowSource.closed, closed: true, noEnd: true);
      expect(w.isOpenAt(opensAt), isFalse);
      expect(w.isOpenAt(DateTime.utc(2026, 9, 5)), isFalse);
    });
  });

  group('isReopenedAt', () {
    test('only for a super-admin reopen that is still open', () {
      final until = DateTime.utc(2026, 10, 31, 18, 29, 59, 999);
      final reopened =
          window(source: RatingWindowSource.opened, closesAt: until);
      expect(reopened.isReopenedAt(DateTime.utc(2026, 10, 2)), isTrue);
      expect(reopened.isReopenedAt(DateTime.utc(2026, 11, 1)), isFalse);
      expect(window().isReopenedAt(DateTime.utc(2026, 9, 5)), isFalse);
    });
  });

  group('fromJson', () {
    test('reads the wire shape', () {
      final w = RatingWindow.fromJson({
        'source': 'OPENED',
        'closed': false,
        'opensAt': '2026-08-31T18:30:00.000Z',
        'closesAt': '2026-10-31T18:29:59.999Z',
        'deadlineAt': '2026-09-10T18:29:59.999Z',
      });
      expect(w, isNotNull);
      expect(w?.source, RatingWindowSource.opened);
      expect(w?.closed, isFalse);
      expect(w?.opensAt, opensAt);
      expect(w?.closesAt, DateTime.utc(2026, 10, 31, 18, 29, 59, 999));
      expect(w?.deadlineAt, deadlineAt);
    });

    test('a null closesAt means no end', () {
      final w = RatingWindow.fromJson({
        'source': 'RETURNED',
        'opensAt': '2026-08-31T18:30:00.000Z',
        'closesAt': null,
      });
      expect(w?.closesAt, isNull);
      expect(w?.isOpenAt(DateTime.utc(2027)), isTrue);
    });

    test('no parsable opensAt means no window, never an invented one', () {
      expect(RatingWindow.fromJson({'source': 'OPENED'}), isNull);
      expect(RatingWindow.fromJson({'source': 'OPENED', 'opensAt': 'soon'}),
          isNull);
      expect(RatingWindow.fromJson('OPENED'), isNull);
      expect(RatingWindow.fromJson(null), isNull);
    });

    test('an unknown source cannot open a closed stage', () {
      final w = RatingWindow.fromJson({
        'source': 'SOMETHING_NEW',
        'closed': true,
        'opensAt': '2026-08-31T18:30:00.000Z',
      });
      expect(w?.source, RatingWindowSource.deadline);
      expect(w?.isOpenAt(DateTime.utc(2026, 9, 5)), isFalse);
    });

    test('round-trips through toJson', () {
      final w = window(source: RatingWindowSource.opened, noEnd: true);
      expect(RatingWindow.fromJson(w.toJson()), w);
    });
  });

  group('parseMap', () {
    Map<String, Object?> entry(String source) => {
          'source': source,
          'closed': source == 'CLOSED',
          'opensAt': '2026-08-31T18:30:00.000Z',
          'closesAt': '2026-09-10T18:29:59.999Z',
        };

    test('keys the five rating stages by exact wire name', () {
      final map = RatingWindow.parseMap({
        'SELF_RATING': entry('DEADLINE'),
        'REPORTING_MANAGER_RATING': entry('DEADLINE'),
        'ACCOUNT_HR_RATING': entry('OPENED'),
        'FINANCE_RATING': entry('DEADLINE'),
        'MANAGEMENT_REVIEW': entry('CLOSED'),
      });
      expect(map?.keys,
          unorderedEquals(ReviewStage.values.where((s) => s.isRatingStage)));
      expect(
          map?[ReviewStage.accountHrRating]?.source, RatingWindowSource.opened);
      expect(map?[ReviewStage.managementReview]?.closed, isTrue);
    });

    test('an unknown or misspelt key is skipped, not filed under self-rating',
        () {
      // ReviewStage.fromApi would turn both of these into SELF_RATING.
      final map = RatingWindow.parseMap({
        'SELF_RATING': entry('DEADLINE'),
        'SELF_RATNG': entry('CLOSED'),
        'SOMETHING_NEW': entry('CLOSED'),
      });
      expect(map?.keys, [ReviewStage.selfRating]);
      expect(map?[ReviewStage.selfRating]?.closed, isFalse);
    });

    test('non-rating stages are ignored', () {
      final map = RatingWindow.parseMap({
        'SELF_RATING': entry('DEADLINE'),
        'INCENTIVE_PAYOUT': entry('CLOSED'),
        'COMPLETED': entry('CLOSED'),
      });
      expect(map?.keys, [ReviewStage.selfRating]);
    });

    test('a malformed entry is skipped and the rest survive', () {
      final map = RatingWindow.parseMap({
        'SELF_RATING': {'source': 'DEADLINE'},
        'FINANCE_RATING': entry('DEADLINE'),
      });
      expect(map?.keys, [ReviewStage.financeRating]);
    });

    test('absent, not a map, or nothing usable means "no server windows"', () {
      expect(RatingWindow.parseMap(null), isNull);
      expect(RatingWindow.parseMap('open'), isNull);
      expect(RatingWindow.parseMap(const <String, Object?>{}), isNull);
      expect(RatingWindow.parseMap({'SELF_RATING': 'open'}), isNull);
    });
  });
}
