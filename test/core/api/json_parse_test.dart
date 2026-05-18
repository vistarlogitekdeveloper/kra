import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/json_parse.dart';

void main() {
  group('JsonParse.parseDouble', () {
    test('parses num (int)', () {
      expect(JsonParse.parseDouble(42), 42.0);
    });

    test('parses num (double)', () {
      expect(JsonParse.parseDouble(3.14), 3.14);
    });

    test('parses numeric string', () {
      expect(JsonParse.parseDouble('7000.00'), 7000.0);
    });

    test('parses string with decimals', () {
      expect(JsonParse.parseDouble('0.05'), 0.05);
    });

    test('returns null on null', () {
      expect(JsonParse.parseDouble(null), isNull);
    });

    test('returns null on empty string', () {
      expect(JsonParse.parseDouble(''), isNull);
    });

    test('returns null on non-numeric string', () {
      expect(JsonParse.parseDouble('hello'), isNull);
    });

    test('handles negative numbers', () {
      expect(JsonParse.parseDouble('-3.5'), -3.5);
    });
  });

  group('JsonParse.parseInt', () {
    test('parses int directly', () {
      expect(JsonParse.parseInt(5), 5);
    });

    test('parses double by truncating', () {
      expect(JsonParse.parseInt(3.9), 3);
    });

    test('parses numeric string', () {
      expect(JsonParse.parseInt('100'), 100);
    });

    test('parses string-double by truncating', () {
      expect(JsonParse.parseInt('7.8'), 7);
    });

    test('returns null on null', () {
      expect(JsonParse.parseInt(null), isNull);
    });

    test('returns null on empty string', () {
      expect(JsonParse.parseInt(''), isNull);
    });
  });

  group('JsonParse.parseDate', () {
    test('parses ISO 8601 string', () {
      final dt = JsonParse.parseDate('2026-05-12T10:30:00Z');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 5);
      expect(dt.day, 12);
    });

    test('returns DateTime unchanged', () {
      final original = DateTime(2026, 1, 1);
      expect(JsonParse.parseDate(original), same(original));
    });

    test('returns null on null', () {
      expect(JsonParse.parseDate(null), isNull);
    });

    test('returns null on empty string', () {
      expect(JsonParse.parseDate(''), isNull);
    });

    test('returns null on malformed string', () {
      expect(JsonParse.parseDate('not-a-date'), isNull);
    });
  });

  group('JsonParse.parseBool', () {
    test('returns bool directly', () {
      expect(JsonParse.parseBool(true), true);
      expect(JsonParse.parseBool(false), false);
    });

    test('treats non-zero numbers as true', () {
      expect(JsonParse.parseBool(1), true);
      expect(JsonParse.parseBool(0), false);
    });

    test('parses string "true" / "false"', () {
      expect(JsonParse.parseBool('true'), true);
      expect(JsonParse.parseBool('false'), false);
      expect(JsonParse.parseBool('TRUE'), true);
    });

    test('returns null on null', () {
      expect(JsonParse.parseBool(null), isNull);
    });
  });

  group('JsonParse.parseMapList', () {
    test('filters non-map entries from list', () {
      final result = JsonParse.parseMapList([
        {'a': 1},
        'not a map',
        42,
        {'b': 2},
      ]);
      expect(result, hasLength(2));
      expect(result[0], {'a': 1});
      expect(result[1], {'b': 2});
    });

    test('returns empty list on null', () {
      expect(JsonParse.parseMapList(null), isEmpty);
    });

    test('returns empty list on non-list', () {
      expect(JsonParse.parseMapList('hello'), isEmpty);
    });
  });
}
