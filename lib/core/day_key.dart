/// A calendar day with no time of day and no time zone, stored as `YYYY-MM-DD`.
///
/// Every "which day is this" question in the app goes through this type, so a
/// day can never be confused with a timestamp and DST cannot shift it.
final class DayKey implements Comparable<DayKey> {
  /// Parts outside 0001-01-01 ... 9999-12-31 give that range's nearest end, and
  /// a month or day past its end is held to it, so every key prints as text
  /// that [parse] reads back to the same key.
  const DayKey(int year, int month, int day)
    : this._inYear(
        year < 1 ? 1 : (year > 9999 ? 9999 : year),
        year < 1
            ? 1
            : (year > 9999 ? 12 : (month < 1 ? 1 : (month > 12 ? 12 : month))),
        year < 1 ? 1 : (year > 9999 ? 31 : day),
      );

  const DayKey._inYear(int year, int month, int day)
    : this._inMonth(
        year,
        month,
        day,
        month == 2
            ? (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28)
            : (month == 4 || month == 6 || month == 9 || month == 11 ? 30 : 31),
      );

  const DayKey._inMonth(this.year, this.month, int day, int lastDay)
    : day = day < 1 ? 1 : (day > lastDay ? lastDay : day);

  /// More days, and months, than lie between 0001-01-01 and 9999-12-31: a
  /// step this long already reaches an end, and a longer one would leave the
  /// range [DateTime] can hold.
  static const _maxDays = 4000000;
  static const _maxMonths = 130000;

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

  /// The day [n] calendar days later (earlier when negative). DST-safe. Stops
  /// at 0001-01-01 and 9999-12-31.
  DayKey addDays(int n) {
    final d = DateTime.utc(year, month, day + n.clamp(-_maxDays, _maxDays));
    return DayKey(d.year, d.month, d.day);
  }

  /// The first day of the month [n] months after this day's month (before, when negative).
  DayKey monthStartPlus(int n) {
    final d = DateTime.utc(year, month + n.clamp(-_maxMonths, _maxMonths), 1);
    return DayKey(d.year, d.month, 1);
  }

  /// The last day of this day's month.
  DayKey get monthEnd => DayKey(year, month, 31);

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
      // addDays stops at 9999-12-31, so that day would repeat for ever.
      if (d == last) return;
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
