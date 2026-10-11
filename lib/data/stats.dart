import '../core/day_key.dart';
import 'models.dart';

/// Share of the "Do" habits that must be done for a day to keep the streak, in percent.
const defaultStreakThreshold = 60;

/// A count out of a total, e.g. 18 of 24 planned habits done.
final class Ratio {
  const Ratio(this.done, this.planned);
  final int done;
  final int planned;

  /// 0..1, or null when nothing was planned (there is nothing to be a share of).
  double? get fraction => planned == 0 ? null : done / planned;

  @override
  bool operator ==(Object other) => other is Ratio && other.done == done && other.planned == planned;

  @override
  int get hashCode => Object.hash(done, planned);

  @override
  String toString() => '$done/$planned';
}

/// How a day counts toward the streak.
enum DayStatus {
  /// Enough was done (or, with nothing planned, nothing was slipped).
  good,

  /// Too little was done, or something was slipped.
  missed,

  /// Nothing was asked of the day: it neither adds to a streak nor breaks it.
  neutral,
}

/// What one day looks like once every habit is counted.
final class DaySummary {
  const DaySummary({
    required this.day,
    required this.planned,
    required this.done,
    required this.slips,
    required this.status,
  });

  final DayKey day;

  /// "Do" habits planned for the day, plus any done on a day they were not planned.
  final int planned;
  final int done;

  /// Slips logged on stay-clear habits.
  final int slips;
  final DayStatus status;

  double? get fraction => planned == 0 ? null : done / planned;
  bool get perfect => planned > 0 && done == planned;
}

/// All habits, entries and seen days, indexed for the counting functions.
///
/// "Do" habits are build habits and avoid habits in `confirm` mode. "Stay-clear"
/// habits are avoid habits in `track` mode: their days start on track, so only
/// slips are stored.
final class Ledger {
  Ledger({
    required Iterable<Habit> habits,
    required Iterable<Entry> entries,
    Iterable<DayKey> seenDays = const [],
  })  : habits = List.unmodifiable(habits),
        _seen = {...seenDays} {
    for (final e in entries) {
      (_byHabit[e.habitId] ??= {})[e.day] = e;
      _entryDays.add(e.day);
    }
  }

  final List<Habit> habits;
  final Set<DayKey> _seen;
  final Map<String, Map<DayKey, Entry>> _byHabit = {};
  final Set<DayKey> _entryDays = {};

  Entry? entryOf(String habitId, DayKey day) => _byHabit[habitId]?[day];

  /// The app was opened (or a check-in answered) that day, or something was logged.
  bool wasSeen(DayKey day) => _seen.contains(day) || _entryDays.contains(day);

  /// The earliest day anything happened, or null when there are no habits.
  DayKey? get firstDay {
    DayKey? first;
    void take(DayKey d) {
      if (first == null || d < first!) first = d;
    }

    for (final h in habits) {
      take(h.createdDay);
    }
    for (final days in _byHabit.values) {
      days.keys.forEach(take);
    }
    return first;
  }
}

DaySummary summarizeDay(Ledger l, DayKey day, {int threshold = defaultStreakThreshold}) {
  var planned = 0;
  var done = 0;
  var slips = 0;
  var tracking = 0;
  for (final h in l.habits) {
    final e = l.entryOf(h.id, day);
    if (h.tracksSlips) {
      if (!h.isActiveOn(day)) continue;
      tracking++;
      if (e?.state == EntryState.slipped) slips++;
      continue;
    }
    if (e?.state == EntryState.skipped) continue;
    if (e?.state == EntryState.done) {
      planned++;
      done++;
    } else if (h.isScheduledOn(day)) {
      planned++;
    }
  }
  final DayStatus status;
  if (planned > 0) {
    status = done * 100 >= planned * threshold ? DayStatus.good : DayStatus.missed;
  } else if (slips > 0) {
    status = DayStatus.missed;
  } else if (tracking > 0 && l.wasSeen(day)) {
    status = DayStatus.good;
  } else {
    status = DayStatus.neutral;
  }
  return DaySummary(day: day, planned: planned, done: done, slips: slips, status: status);
}

/// Days in a row that were good, counting back from [today]. A [today] that is
/// still short of the threshold is pending and does not break the run.
int currentStreak(Ledger l, DayKey today, {int threshold = defaultStreakThreshold}) {
  final first = l.firstDay;
  if (first == null) return 0;
  var n = 0;
  for (var d = today; d >= first; d = d.addDays(-1)) {
    switch (summarizeDay(l, d, threshold: threshold).status) {
      case DayStatus.good:
        n++;
      case DayStatus.neutral:
        break;
      case DayStatus.missed:
        if (d != today) return n;
    }
  }
  return n;
}

/// The longest run of good days up to [today]. A [today] still short of the
/// threshold only ends a run that has already been counted.
int bestStreak(Ledger l, DayKey today, {int threshold = defaultStreakThreshold}) {
  final first = l.firstDay;
  if (first == null) return 0;
  var run = 0;
  var best = 0;
  for (final d in first.through(today)) {
    switch (summarizeDay(l, d, threshold: threshold).status) {
      case DayStatus.good:
        run++;
        if (run > best) best = run;
      case DayStatus.neutral:
        break;
      case DayStatus.missed:
        run = 0;
    }
  }
  return best;
}

/// Planned and done "Do" habits summed over [from]..[to]. Days before a habit
/// existed plan nothing, so they neither help nor hurt.
Ratio rateOver(Ledger l, DayKey from, DayKey to, {int threshold = defaultStreakThreshold}) {
  var done = 0;
  var planned = 0;
  for (final d in from.through(to)) {
    final s = summarizeDay(l, d, threshold: threshold);
    done += s.done;
    planned += s.planned;
  }
  return Ratio(done, planned);
}

/// Days in [from]..[to] on which every planned "Do" habit was done.
int perfectDays(Ledger l, DayKey from, DayKey to) =>
    from.through(to).where((d) => summarizeDay(l, d).perfect).length;

/// A single habit's run of days.
final class HabitStreak {
  const HabitStreak({required this.current, required this.best});
  final int current;
  final int best;

  @override
  bool operator ==(Object other) =>
      other is HabitStreak && other.current == current && other.best == best;

  @override
  int get hashCode => Object.hash(current, best);

  @override
  String toString() => 'HabitStreak(current: $current, best: $best)';
}

/// One habit's streaks as of [today].
///
/// Do habit: consecutive planned days done; skipped days are passed over and
/// [today], while still open, does not break the run.
/// Stay-clear habit: days since the last slip, counting only days the app saw.
HabitStreak habitStreak(Ledger l, Habit h, DayKey today) {
  final last = (h.endDay != null && h.endDay! < today) ? h.endDay! : today;
  var run = 0;
  var best = 0;
  for (final d in h.createdDay.through(last)) {
    final e = l.entryOf(h.id, d);
    if (h.tracksSlips) {
      if (e?.state == EntryState.slipped) {
        run = 0;
      } else if (l.wasSeen(d)) {
        run++;
        if (run > best) best = run;
      }
      continue;
    }
    if (e?.state == EntryState.skipped) continue;
    if (e?.state == EntryState.done) {
      run++;
      if (run > best) best = run;
    } else if (h.isScheduledOn(d) && d != today) {
      run = 0;
    }
  }
  return HabitStreak(current: run, best: best);
}

/// One habit's done-out-of-planned over [from]..[to]. For a stay-clear habit,
/// days without a slip out of days the app saw.
Ratio habitRate(Ledger l, Habit h, DayKey from, DayKey to) {
  var done = 0;
  var planned = 0;
  for (final d in from.through(to)) {
    final e = l.entryOf(h.id, d);
    if (h.tracksSlips) {
      if (!h.isActiveOn(d) || !l.wasSeen(d)) continue;
      planned++;
      if (e?.state != EntryState.slipped) done++;
      continue;
    }
    if (e?.state == EntryState.skipped) continue;
    if (e?.state == EntryState.done) {
      planned++;
      done++;
    } else if (h.isScheduledOn(d)) {
      planned++;
    }
  }
  return Ratio(done, planned);
}
