import 'package:intl/intl.dart';

/// Centralised, locale-aware formatters used across the HR module.
///
/// Currency uses the Indian numbering grouping (1,37,835 not 137,835)
/// because every payout in this app is in INR and HR is the audience.
class HrFormatters {
  HrFormatters._();

  // ───── Date ─────

  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _shortDate = DateFormat('d MMM');

  static String date(DateTime d) => _date.format(d);
  static String dateOrDash(DateTime? d) => d == null ? '—' : _date.format(d);
  static String shortDate(DateTime d) => _shortDate.format(d);

  // ───── Currency ─────

  static final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static String currencyInr(num value) => _inr.format(value);

  // ───── Relative time ─────
  // Used by the activity feed. Avoids pulling in a heavy package — the
  // ranges below ("just now" / "2 hours ago" / "3 days ago") cover every
  // case the HR home feed will encounter in practice.

  static String relativeTime(DateTime then) {
    final delta = DateTime.now().difference(then);
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

  // ───── Number with sign ─────

  static String signedPercent(double value) {
    final fixed = value.abs().toStringAsFixed(1);
    final stripped = fixed.endsWith('.0')
        ? fixed.substring(0, fixed.length - 2)
        : fixed;
    if (value > 0) return '+$stripped%';
    if (value < 0) return '−$stripped%';
    return '$stripped%';
  }

  /// Formats weightage as "30%" or "33.5%" — drops the `.0` suffix when
  /// the value is a whole number to keep the indicator readable.
  static String weightagePercent(double value) {
    final rounded = (value * 10).roundToDouble() / 10;
    if (rounded == rounded.roundToDouble()) {
      return '${rounded.toInt()}%';
    }
    return '${rounded.toStringAsFixed(1)}%';
  }
}
