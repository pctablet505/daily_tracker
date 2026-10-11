import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';

/// Monday 2026-10-05 ... Sunday 2026-10-11.
const mon = DayKey(2026, 10, 5);
const tue = DayKey(2026, 10, 6);
const wed = DayKey(2026, 10, 7);
const thu = DayKey(2026, 10, 8);
const fri = DayKey(2026, 10, 9);
const sat = DayKey(2026, 10, 10);
const sun = DayKey(2026, 10, 11);

final _logged = DateTime.utc(2026, 10, 11, 12);

/// Bit mask for the given weekdays (1 = Monday ... 7 = Sunday).
int daysOf(Iterable<int> weekdays) => weekdays.fold(0, (m, w) => m | (1 << (w - 1)));

Habit habit(
  String id, {
  DayKey created = mon,
  DayKey? end,
  HabitKind kind = HabitKind.build,
  AvoidMode avoidMode = AvoidMode.track,
  int mask = Habit.everyDay,
  LogType logType = LogType.tick,
  double? goal,
  String? area,
}) =>
    Habit(
      id: id,
      name: 'Habit $id',
      createdDay: created,
      endDay: end,
      kind: kind,
      avoidMode: avoidMode,
      daysMask: mask,
      logType: logType,
      goal: goal,
      area: area,
    );

Habit stayClear(String id, {DayKey created = mon, DayKey? end}) =>
    habit(id, kind: HabitKind.avoid, created: created, end: end);

Entry entry(String habitId, DayKey day, [EntryState state = EntryState.done, double? value]) =>
    Entry(habitId: habitId, day: day, state: state, loggedAt: _logged, value: value);

Entry slip(String habitId, DayKey day) => entry(habitId, day, EntryState.slipped);
