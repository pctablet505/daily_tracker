import 'package:intl/intl.dart';

import '../core/day_key.dart';
import '../data/models.dart';

final _long = DateFormat('d MMMM');
final _short = DateFormat('EEE d MMM');
final _weekday = DateFormat('EEEE');
final _month = DateFormat('MMMM yyyy');
final _letter = DateFormat('EEEEE');

String weekdayName(DayKey d) => _weekday.format(d.date);

/// "11 October"
String longDate(DayKey d) => _long.format(d.date);

/// "Fri 9 Oct"
String shortDate(DayKey d) => _short.format(d.date);

String monthTitle(DayKey d) => _month.format(d.date);

/// One-letter weekday: M T W T F S S.
String weekdayLetter(DayKey d) => _letter.format(d.date);

/// 75.0 -> "75", 75.5 -> "75.5", 0.25 -> "0.25". Never trailing zeros.
String formatAmount(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

String formatAmountUnit(double v, String? unit) => unit == null || unit.isEmpty ? formatAmount(v) : '${formatAmount(v)} $unit';

String dayPartName(DayPart p) => switch (p) {
      DayPart.morning => 'Morning',
      DayPart.afternoon => 'Afternoon',
      DayPart.evening => 'Evening',
      DayPart.anytime => 'Anytime',
    };

/// "8:00 AM" or "08:00" depending on [use24h].
String formatMinutes(int minutes, {required bool use24h}) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (use24h) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

const _dayLetters = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Every day", "Weekdays", "Mon, Wed, Fri".
String scheduleSummary(int mask) {
  if (mask == Habit.everyDay) return 'Every day';
  if (mask == Habit.weekdaysOnly) return 'Weekdays';
  if (mask == 96) return 'Weekends';
  final days = [for (var i = 0; i < 7; i++) if ((mask >> i) & 1 == 1) _dayLetters[i]];
  return days.isEmpty ? 'Never' : days.join(', ');
}

String plural(int n, String one, [String? many]) => n == 1 ? '$n $one' : '$n ${many ?? '${one}s'}';

/// The grey line under a to-do title.
String habitMeta(Habit h, {Entry? entry, double? lastValue, int photoCount = 0}) {
  final parts = <String>[dayPartName(h.dayPart)];
  switch (h.logType) {
    case LogType.number:
      final v = entry?.value;
      if (v != null && h.goal != null) {
        parts.add('${formatAmount(v)} of ${formatAmountUnit(h.goal!, h.unit)}');
      } else if (lastValue != null) {
        parts.add('last ${formatAmountUnit(lastValue, h.unit)}');
      } else if (h.goal != null) {
        parts.add('goal ${formatAmountUnit(h.goal!, h.unit)}');
      }
    case LogType.note:
      parts.add('note');
    case LogType.photo:
      if (photoCount > 0) parts.add(plural(photoCount, 'photo'));
    case LogType.tick:
      break;
  }
  return parts.join(' · ');
}

/// The label on a row's action button.
String logActionLabel(Habit h) => switch (h.logType) {
      LogType.number => 'Log ${h.unit == null || h.unit!.isEmpty ? 'amount' : h.unit}',
      LogType.note => 'Add note',
      LogType.photo => 'Take photo',
      LogType.tick => 'Done',
    };
