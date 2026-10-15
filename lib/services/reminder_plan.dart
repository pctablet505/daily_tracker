import 'dart:convert';

import '../core/day_key.dart';
import '../data/models.dart';
import '../data/stats.dart';
import '../state/settings.dart';

enum ReminderKind { habit, checkIn }

/// One notification to show at a local wall-clock time.
final class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.when,
    required this.kind,
    required this.title,
    required this.body,
    this.habitId,
    this.forDay,
    this.markable = false,
  });

  final int id;
  final DateTime when;
  final ReminderKind kind;
  final String title;
  final String body;
  final String? habitId;

  /// The day the reminder is about. Quiet hours can show it on the next morning,
  /// and the Done button must still mark the day it was for.
  final DayKey? forDay;

  /// A tick habit can be finished from the notification's Done button.
  final bool markable;

  PlannedReminder withId(int newId) => PlannedReminder(
    id: newId,
    when: when,
    kind: kind,
    title: title,
    body: body,
    habitId: habitId,
    forDay: forDay,
    markable: markable,
  );

  /// What the notification opens when tapped.
  String get payload =>
      habitId == null ? 'today' : habitPayload(habitId!, forDay);
}

/// `habit:ID@DAY`: where a reminder opens, and which day its Done button marks.
String habitPayload(String habitId, DayKey? day) =>
    day == null ? 'habit:$habitId' : 'habit:$habitId@$day';

/// The reverse of [habitPayload]; null for any other payload ("today"), and
/// for a day that does not parse, which must not be taken for today.
({String habitId, DayKey? day})? parseHabitPayload(String payload) {
  if (!payload.startsWith('habit:')) return null;
  final rest = payload.substring('habit:'.length);
  final at = rest.lastIndexOf('@');
  if (at < 0) return rest.isEmpty ? null : (habitId: rest, day: null);
  final id = rest.substring(0, at);
  final day = DayKey.tryParse(rest.substring(at + 1));
  return id.isEmpty || day == null ? null : (habitId: id, day: day);
}

/// Android allows an app 500 pending alarms; keep well under that, soonest first.
const maxPlannedReminders = 400;

/// Planned reminders take ids below this; snoozed ones take ids from it.
const snoozeIdBase = 1 << 30;

/// The same reminder gets the same id in every plan (FNV-1a of what it is for).
/// Ids by position would move on each re-plan, and cancelling a pending id
/// also removes a notification with that id already in the shade.
int _idFor(PlannedReminder r) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(
    '${r.kind.name}|${r.habitId ?? ''}|${r.forDay}',
  )) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return 1 + h % (snoozeIdBase - 1);
}

/// A reminder time moved out of quiet hours: to the moment the window ends.
/// Returns minutes after midnight and whether it moved to the next day.
({int minutes, bool nextDay}) _shiftOutOfQuiet(int minutes, Settings s) {
  if (!s.quietHoursOn) return (minutes: minutes, nextDay: false);
  final start = s.quietStartMinutes;
  final end = s.quietEndMinutes;
  if (start == end) return (minutes: minutes, nextDay: false);
  if (start < end) {
    return minutes >= start && minutes < end
        ? (minutes: end, nextDay: false)
        : (minutes: minutes, nextDay: false);
  }
  // The window crosses midnight: [start, 24:00) and [00:00, end).
  if (minutes >= start) return (minutes: end, nextDay: true);
  if (minutes < end) return (minutes: end, nextDay: false);
  return (minutes: minutes, nextDay: false);
}

/// The notifications to have scheduled, from [now] for [horizonDays] days.
///
/// Reminders are planned one day at a time (not as a repeating alarm) so one
/// can be left out when the habit is already done that day. The plan is rebuilt
/// whenever the app opens or data changes.
List<PlannedReminder> planReminders(
  Ledger ledger, {
  required Settings settings,
  required DateTime now,
  required int horizonDays,
  bool includeCarryOver = false,
}) {
  if (!settings.remindersOn || horizonDays <= 0) return const [];
  final today = DayKey.fromDate(now);
  final out = <PlannedReminder>[];

  void add(
    DayKey day,
    int minutes,
    ReminderKind kind,
    String title,
    String body,
    String? habitId, {
    bool markable = false,
    bool carryOverOnly = false,
  }) {
    if (minutes < 0 || minutes >= 24 * 60) return;
    final shifted = _shiftOutOfQuiet(minutes, settings);
    if (carryOverOnly && !shifted.nextDay) return;
    final target = shifted.nextDay ? day.addDays(1) : day;
    final when = DateTime(
      target.year,
      target.month,
      target.day,
      shifted.minutes ~/ 60,
      shifted.minutes % 60,
    );
    if (!when.isAfter(now)) return;
    out.add(
      PlannedReminder(
        id: 0,
        when: when,
        kind: kind,
        title: title,
        body: body,
        habitId: habitId,
        forDay: day,
        markable: markable,
      ),
    );
  }

  final startOffset = includeCarryOver ? -1 : 0;
  for (var i = startOffset; i < horizonDays; i++) {
    final day = today.addDays(i);
    final carryOverOnly = i < 0;
    for (final h in ledger.habits) {
      final at = h.reminderMinutes;
      if (at == null || h.tracksSlips || !h.isScheduledOn(day)) continue;
      final state = ledger.entryOf(h.id, day)?.state;
      if (state == EntryState.done || state == EntryState.skipped) continue;
      add(
        day,
        at,
        ReminderKind.habit,
        h.name,
        h.kind == HabitKind.avoid
            ? 'Did you stay clear today?'
            : 'Time for this one.',
        h.id,
        markable: h.logType == LogType.tick,
        carryOverOnly: carryOverOnly,
      );
    }
    if (settings.eveningCheckInOn &&
        (!carryOverOnly || !ledger.wasSeen(day)) &&
        ledger.habits.any((h) => h.tracksSlips && h.isActiveOn(day))) {
      add(
        day,
        settings.eveningCheckInMinutes,
        ReminderKind.checkIn,
        'How did today go?',
        'Tap to log a slip, or just open the app to keep your day on track.',
        null,
        carryOverOnly: carryOverOnly,
      );
    }
  }
  out.sort((a, b) {
    final byTime = a.when.compareTo(b.when);
    return byTime != 0 ? byTime : a.payload.compareTo(b.payload);
  });
  final used = <int>{};
  final kept = <PlannedReminder>[];
  for (final r in out.take(maxPlannedReminders)) {
    var id = _idFor(r);
    // Two reminders of one plan that hash alike: the later one steps on.
    while (!used.add(id)) {
      id = id == snoozeIdBase - 1 ? 1 : id + 1;
    }
    kept.add(r.withId(id));
  }
  return kept;
}
