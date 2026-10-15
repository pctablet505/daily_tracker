/// A calendar day with no time of day and no time zone, stored as `YYYY-MM-DD`.
///
/// Every "which day is this" question in the app goes through this type, so a
/// day can never be confused with a timestamp and DST cannot shift it.
final class DayKey implements Comparable<DayKey> {
  const DayKey(this.year, this.month, this.day);

  /// The local calendar day of [date].
  factory DayKey.fromDate(DateTime date) =>
      DayKey(date.year, date.month, date.day);

  /// Parses `YYYY-MM-DD`. Throws [FormatException] for anything else, including
  /// impossible dates such as `2026-02-30`.
  factory DayKey.parse(String text) =>
      tryParse(text) ?? (throw FormatException('Not a YYYY-MM-DD day', text));

  static DayKey? tryParse(String text) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (m == null) return null;
    final y = int.parse(m[1]!);
    final mo = int.parse(m[2]!);
    final d = int.parse(m[3]!);
    if (y < 1) return null;
    final check = DateTime.utc(y, mo, d);
    if (check.year != y || check.month != mo || check.day != d) return null;
    return DayKey(y, mo, d);
  }

  final int year;
  final int month;
  final int day;

  /// Local midnight at the start of this day.
  DateTime get date => DateTime(year, month, day);

  /// 1 = Monday ... 7 = Sunday, as in [DateTime.weekday].
  int get weekday => DateTime.utc(year, month, day).weekday;

  /// The day [n] calendar days later (earlier when negative). DST-safe.
  DayKey addDays(int n) {
    final d = DateTime.utc(year, month, day + n);
    return DayKey(d.year, d.month, d.day);
  }

  /// The first day of the month [n] months after this day's month (before, when negative).
  DayKey monthStartPlus(int n) {
    final d = DateTime.utc(year, month + n, 1);
    return DayKey(d.year, d.month, 1);
  }

  /// The last day of this day's month.
  DayKey get monthEnd => monthStartPlus(1).addDays(-1);

  /// Whole calendar days from this day to [other] (negative when [other] is earlier).
  int daysUntil(DayKey other) => DateTime.utc(
    other.year,
    other.month,
    other.day,
  ).difference(DateTime.utc(year, month, day)).inDays;

  /// Every day from this day to [last], both included. Empty when [last] is earlier.
  Iterable<DayKey> through(DayKey last) sync* {
    for (var d = this; d <= last; d = d.addDays(1)) {
      yield d;
    }
  }

  bool operator <(DayKey o) => compareTo(o) < 0;
  bool operator <=(DayKey o) => compareTo(o) <= 0;
  bool operator >(DayKey o) => compareTo(o) > 0;
  bool operator >=(DayKey o) => compareTo(o) >= 0;

  @override
  int compareTo(DayKey other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is DayKey &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
