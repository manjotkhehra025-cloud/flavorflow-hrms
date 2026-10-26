import 'package:intl/intl.dart';

/// Formatting helpers (INR currency, dates, times).
class Fmt {
  Fmt._();

  static final NumberFormat _inr =
      NumberFormat.currency(locale: 'en_IN', symbol: '\u20B9', decimalDigits: 0);
  static final NumberFormat _inr2 =
      NumberFormat.currency(locale: 'en_IN', symbol: '\u20B9', decimalDigits: 2);

  /// e.g. 1,25,000 -> "\u20B91,25,000"
  static String inr(num value) => _inr.format(value);
  static String inrPrecise(num value) => _inr2.format(value);

  static String date(DateTime d) => DateFormat('dd MMM yyyy').format(d);
  static String shortDate(DateTime d) => DateFormat('dd MMM').format(d);
  static String weekday(DateTime d) => DateFormat('EEE').format(d);
  static String fullDay(DateTime d) => DateFormat('EEEE, dd MMM yyyy').format(d);
  static String month(DateTime d) => DateFormat('MMMM yyyy').format(d);
  static String time(DateTime? d) =>
      d == null ? '--:--' : DateFormat('hh:mm a').format(d);

  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${h}h ${m}m';
  }
}

/// Strips the time part of a [DateTime].
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
