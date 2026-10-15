import '../core/day_key.dart';
import '../data/models.dart';
import '../data/stats.dart';

enum RowKind { todo, partial, done, skipped, onTrack, slipped }

/// One habit on one day, as the Today list shows it.
final class HabitRow {
  const HabitRow({
    required this.habit,
    required this.entry,
    required this.kind,
    required this.streak,
    this.lastValue,
    this.photoCount = 0,
  });
  final Habit habit;
  final Entry? entry;
  final RowKind kind;

  /// The habit's current streak as of the day shown.
  final int streak;

  /// The most recent number logged on an earlier day (number habits).
  final double? lastValue;

  /// Photos logged up to and including the day shown (photo habits).
  final int photoCount;
}

/// What the Today screen lists for one day.
final class TodayView {
  const TodayView({
    required this.day,
    required this.toDo,
    required this.stayClear,
    required this.finished,
    required this.summary,
    required this.hasAnyHabit,
  });

  final DayKey day;
  final List<HabitRow> toDo;
  final List<HabitRow> stayClear;
  final List<HabitRow> finished;

  /// The whole day's count, not limited by a search.
  final DaySummary summary;

  /// There is at least one habit in the app (used to tell "nothing yet" from "no match").
  final bool hasAnyHabit;

  bool get isEmpty => toDo.isEmpty && stayClear.isEmpty && finished.isEmpty;
}

bool _matches(Habit h, String q) {
  if (q.isEmpty) return true;
  return h.name.toLowerCase().contains(q) ||
      (h.description?.toLowerCase().contains(q) ?? false) ||
      (h.area?.toLowerCase().contains(q) ?? false);
}

int _byPartThenOrder(HabitRow a, HabitRow b) {
  final p = a.habit.dayPart.index.compareTo(b.habit.dayPart.index);
  if (p != 0) return p;
  final o = a.habit.sortOrder.compareTo(b.habit.sortOrder);
  return o != 0 ? o : a.habit.name.compareTo(b.habit.name);
}

/// The list for [day]. [today] is the real day ([day] when not given): only it
/// is still open, so a past day not done ends a row's streak.
TodayView buildTodayView(
  Ledger l,
  DayKey day, {
  DayKey? today,
  String query = '',
  int threshold = defaultStreakThreshold,
  bool Function(String photoName)? photoExists,
}) {
  final q = query.trim().toLowerCase();
  final toDo = <HabitRow>[];
  final stayClear = <HabitRow>[];
  final finished = <HabitRow>[];
  for (final h in l.habits) {
    if (!h.isActiveOn(day)) continue;
    final e = l.entryOf(h.id, day);
    if (h.tracksSlips) {
      if (!_matches(h, q)) continue;
      if (e?.state == EntryState.skipped) {
        finished.add(
          HabitRow(
            habit: h,
            entry: e,
            kind: RowKind.skipped,
            streak: habitStreak(l, h, day, today: today).current,
          ),
        );
        continue;
      }
      stayClear.add(
        HabitRow(
          habit: h,
          entry: e,
          kind: e?.state == EntryState.slipped
              ? RowKind.slipped
              : RowKind.onTrack,
          streak: habitStreak(l, h, day, today: today).current,
        ),
      );
      continue;
    }
    // A slip on a Do habit (left by an edit from stay-clear) counts for
    // nothing in the day summary, so it does not bring an unplanned day here.
    final listed =
        h.isScheduledOn(day) || (e != null && e.state != EntryState.slipped);
    if (!listed || !_matches(h, q)) continue;
    final kind = switch (e?.state) {
      EntryState.done => RowKind.done,
      EntryState.skipped => RowKind.skipped,
      // Only an amount can be part of the way; any other kind is still to do.
      EntryState.partial when h.logType == LogType.number => RowKind.partial,
      _ => RowKind.todo,
    };
    final history = l.entriesOf(h.id);
    final row = HabitRow(
      habit: h,
      entry: e,
      kind: kind,
      streak: habitStreak(l, h, day, today: today).current,
      lastValue: h.logType == LogType.number
          ? history
                .where(
                  (x) =>
                      x.day < day &&
                      x.value != null &&
                      x.state != EntryState.skipped,
                )
                .lastOrNull
                ?.value
          : null,
      photoCount: h.logType == LogType.photo
          ? history
                .where(
                  (x) =>
                      x.day <= day &&
                      x.photoPath != null &&
                      x.state != EntryState.skipped &&
                      (photoExists?.call(x.photoPath!) ?? true),
                )
                .length
          : 0,
    );
    (kind == RowKind.done || kind == RowKind.skipped ? finished : toDo).add(
      row,
    );
  }
  toDo.sort(_byPartThenOrder);
  stayClear.sort(_byPartThenOrder);
  finished.sort(_byPartThenOrder);
  return TodayView(
    day: day,
    toDo: toDo,
    stayClear: stayClear,
    finished: finished,
    summary: summarizeDay(l, day, threshold: threshold),
    hasAnyHabit: l.habits.any((h) => !h.isArchived || h.isActiveOn(day)),
  );
}
