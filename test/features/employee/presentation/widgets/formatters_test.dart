import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/presentation/widgets/_formatters.dart';

void main() {
  group('EmployeeFormatters.scoreOutOf', () {
    test('trims a whole-number maxScore so it reads "8/10" not "8/10.0"', () {
      // Regression: maxScore arrives as a double (JsonParse.parseDouble),
      // and the old code used maxScore.toString() → "10.0".
      expect(EmployeeFormatters.scoreOutOf(8, 10.0), '8/10');
    });

    test('keeps a genuinely fractional maxScore', () {
      expect(EmployeeFormatters.scoreOutOf(3.5, 7.5), '3.5/7.5');
    });

    test('trims the numerator too', () {
      expect(EmployeeFormatters.scoreOutOf(10.0, 10.0), '10/10');
    });
  });
}
