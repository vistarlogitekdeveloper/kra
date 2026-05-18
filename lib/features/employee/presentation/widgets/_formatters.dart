import 'package:intl/intl.dart';

/// Module-private formatters for the Employee feature.
///
/// Mirrors the HR module's formatter helper rather than depending on it
/// directly — keeps each feature self-contained so a future split into
/// separate packages doesn't fight the import graph.
///
/// Currency uses Indian grouping (1,37,835) because every figure in this
/// app is in INR.
class EmployeeFormatters {
  EmployeeFormatters._();

  // ───── Date ─────

  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _shortDate = DateFormat('d MMM');
  static final DateFormat _monthYear = DateFormat('MMMM yyyy');
  static final DateFormat _today = DateFormat('EEEE, d MMMM yyyy');

  static String date(DateTime d) => _date.format(d);
  static String dateOrDash(DateTime? d) => d == null ? '—' : _date.format(d);
  static String shortDate(DateTime d) => _shortDate.format(d);
  static String monthYear(DateTime d) => _monthYear.format(d);
  static String today(DateTime d) => _today.format(d);

  // ───── Currency ─────

  static final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// Indian rupee with grouping but no paise. Use [currencyInrPrecise]
  /// when the source amount has fractional rupees worth showing.
  static String currencyInr(num value) => _inr.format(value);

  static final NumberFormat _inrPrecise = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static String currencyInrPrecise(num value) => _inrPrecise.format(value);

  // ───── Score / percentage ─────

  /// Trims a trailing `.0` so 76.0 renders as "76". Used on totals,
  /// where whole-number scores feel cleaner without the decimal.
  static String score(double value, {int fractionDigits = 1}) {
    final fixed = value.toStringAsFixed(fractionDigits);
    if (fixed.endsWith('.0')) return fixed.substring(0, fixed.length - 2);
    return fixed;
  }

  static String scoreOutOf(double value, num maxScore) =>
      '${score(value)}/${maxScore.toString()}';

  static String percent(double value, {int fractionDigits = 1}) {
    final pretty = score(value, fractionDigits: fractionDigits);
    return '$pretty%';
  }

  // ───── Weightage (0–100, may be fractional) ─────

  static String weightagePercent(double value) {
    final rounded = (value * 10).roundToDouble() / 10;
    if (rounded == rounded.roundToDouble()) {
      return '${rounded.toInt()}%';
    }
    return '${rounded.toStringAsFixed(1)}%';
  }

  // ───── Relative time ─────

  static String relativeTime(DateTime then) {
    final delta = DateTime.now().difference(then);
    if (delta.isNegative) return 'just now';
    if (delta.inSeconds < 45) return 'just now';
    if (delta.inMinutes < 1) return '${delta.inSeconds} seconds ago';
    if (delta.inMinutes < 60) {
      final m = delta.inMinutes;
      return m == 1 ? 'a minute ago' : '$m minutes ago';
    }
    if (delta.inHours < 24) {
      final h = delta.inHours;
      return h == 1 ? 'an hour ago' : '$h hours ago';
    }
    if (delta.inDays < 7) {
      final d = delta.inDays;
      return d == 1 ? 'yesterday' : '$d days ago';
    }
    if (delta.inDays < 30) {
      final w = (delta.inDays / 7).floor();
      return w == 1 ? 'last week' : '$w weeks ago';
    }
    return date(then);
  }
}
