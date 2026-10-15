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
  bool operator ==(Object other) =>
      other is Ratio && other.done == done && other.planned == planned;

  @override
  int get hashCode => Object.hash(done, planned);

  @override
  String toString() => '$done/$planned';
}

/// How a day counts toward the streak.
enum DayStatus {
  /// Enough was done (or, with nothing planned, nothing was slipped).
  good,

  /// Too little was done, or (on a day with nothing else planned) something was slipped.
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

  /// Everything planned was done and nothing was slipped. With no Do habit
  /// planned, a good day is perfect: the stay-clear habits held on a day the
  /// app was seen.
  bool get perfect =>
      planned > 0 ? done == planned && slips == 0 : status == DayStatus.good;
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
  }) : habits = List.unmodifiable(habits),
       _seen = {...seenDays} {
    for (final e in entries) {
      (_byHabit[e.habitId] ??= {})[e.day] = e;
      _entryDays.add(e.day);
    }
    _activeDays = {..._seen, ..._entryDays}.toList()..sort();
  }

  final List<Habit> habits;
  final Set<DayKey> _seen;
  final Map<String, Map<DayKey, Entry>> _byHabit = {};
  final Set<DayKey> _entryDays = {};
  late final List<DayKey> _activeDays;

  Entry? entryOf(String habitId, DayKey day) => _byHabit[habitId]?[day];

  /// All entries of one habit, oldest first.
  List<Entry> entriesOf(String habitId) {
    final days = _byHabit[habitId];
    if (days == null) return const [];
    return days.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  }

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

  /// The earliest day that was seen or has an entry, or null if none.
  DayKey? get _firstActiveDay => _activeDays.firstOrNull;

  /// The earliest day any habit started, or null when there are no habits.
  late final DayKey? _firstStart = habits.fold<DayKey?>(
    null,
    (first, h) => first == null || h.createdDay < first ? h.createdDay : first,
  );
}

DaySummary summarizeDay(
  Ledger l,
  DayKey day, {
  int threshold = defaultStreakThreshold,
}) {
  final clampedThreshold = threshold.clamp(1, 100);
  var planned = 0;
  var done = 0;
  var slips = 0;
  var tracking = 0;
  for (final h in l.habits) {
    if (!h.isActiveOn(day)) continue;
    final e = l.entryOf(h.id, day);
    if (e?.state == EntryState.skipped) continue;
    if (h.tracksSlips) {
      tracking++;
      if (e?.state == EntryState.slipped) slips++;
      continue;
    }
    if (e?.state == EntryState.done) {
      planned++;
      done++;
    } else if (h.isScheduledOn(day) || e?.state == EntryState.partial) {
      planned++;
    }
  }
  final DayStatus status;
  if (planned > 0) {
    status = done * 100 >= planned * clampedThreshold
        ? DayStatus.good
        : DayStatus.missed;
  } else if (slips > 0) {
    status = DayStatus.missed;
  } else if (tracking > 0 && l.wasSeen(day)) {
    status = DayStatus.good;
  } else {
    status = DayStatus.neutral;
  }
  return DaySummary(
    day: day,
    planned: planned,
    done: done,
    slips: slips,
    status: status,
  );
}

/// Days in a row that were good, counting back from [today]. A [today] that is
/// still short of the threshold is pending and does not break the run.
int currentStreak(
  Ledger l,
  DayKey today, {
  int threshold = defaultStreakThreshold,
}) {
  final seen = l._firstActiveDay;
  final started = l._firstStart;
  if (seen == null || started == null) return 0;
  // Before the first habit started every day is neutral.
  final first = seen > started ? seen : started;
  var n = 0;
  for (var d = today; d >= first; d = d.addDays(-1)) {
    final s = summarizeDay(l, d, threshold: threshold);
    switch (s.status) {
      case DayStatus.good:
        n++;
      case DayStatus.neutral:
        break;
      case DayStatus.missed:
        if (d != today || (s.planned == 0 && s.slips > 0)) return n;
    }
  }
  return n;
}

/// The longest run of good days up to [today]. A [today] still short of the
/// threshold only ends a run that has already been counted.
int bestStreak(
  Ledger l,
  DayKey today, {
  int threshold = defaultStreakThreshold,
}) {
  final first = l._firstActiveDay;
  if (first == null || first > today) return 0;
  var run = 0;
  var best = 0;
  var i = 0;
  for (var d = first; d <= today;) {
    while (i < l._activeDays.length && l._activeDays[i] < d) {
      i++;
    }
    if (run == 0) {
      if (i >= l._activeDays.length || l._activeDays[i] > today) break;
      if (l._activeDays[i] > d) d = l._activeDays[i];
    }
    switch (summarizeDay(l, d, threshold: threshold).status) {
      case DayStatus.good:
        run++;
        if (run > best) best = run;
      case DayStatus.neutral:
        break;
      case DayStatus.missed:
        run = 0;
    }
    d = d.addDays(1);
  }
  return best;
}

/// Planned and done "Do" habits summed over [from]..[to]. Days before a habit
/// existed plan nothing, so they neither help nor hurt.
Ratio rateOver(
  Ledger l,
  DayKey from,
  DayKey to, {
  int threshold = defaultStreakThreshold,
}) {
  var done = 0;
  var planned = 0;
  for (final d in from.through(to)) {
    final s = summarizeDay(l, d, threshold: threshold);
    done += s.done;
    planned += s.planned;
  }
  if (planned == 0) {
    for (final h in l.habits) {
      if (!h.tracksSlips) continue;
      final r = habitRate(l, h, from, to);
      done += r.done;
      planned += r.planned;
    }
  }
  return Ratio(done, planned);
}

/// Days in [from]..[to] that were [DaySummary.perfect].
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

/// One habit's streaks as of [day], looked at on [today] (the real day; [day]
/// when not given).
///
/// Do habit: consecutive planned days done; skipped days are passed over and
/// [today], while still open, does not break the run. A [day] before [today]
/// is over, so missing it does.
/// Stay-clear habit: days since the last slip, counting only days the app saw.
HabitStreak habitStreak(Ledger l, Habit h, DayKey day, {DayKey? today}) {
  final open = today ?? day;
  final last = (h.endDay != null && h.endDay! < day) ? h.endDay! : day;
  final entries = l.entriesOf(h.id);
  final DayKey? earliest = h.tracksSlips
      ? l._firstActiveDay
      : entries.firstOrNull?.day;
  if (earliest == null) return const HabitStreak(current: 0, best: 0);
  final start = earliest > h.createdDay ? earliest : h.createdDay;
  if (start > last) return const HabitStreak(current: 0, best: 0);
  var run = 0;
  var best = 0;
  if (h.tracksSlips) {
    for (final d in l._activeDays) {
      if (d < start) continue;
      if (d > last) break;
      final e = l.entryOf(h.id, d);
      if (e?.state == EntryState.skipped) continue;
      if (e?.state == EntryState.slipped) {
        run = 0;
      } else if (l.wasSeen(d)) {
        run++;
        if (run > best) best = run;
      }
    }
    return HabitStreak(current: run, best: best);
  }
  var i = 0;
  for (var d = start; d <= last;) {
    while (i < entries.length && entries[i].day < d) {
      i++;
    }
    if (run == 0) {
      if (i >= entries.length || entries[i].day > last) break;
      if (entries[i].day > d) d = entries[i].day;
    }
    final e = l.entryOf(h.id, d);
    if (e?.state != EntryState.skipped) {
      if (e?.state == EntryState.done) {
        run++;
        if (run > best) best = run;
      } else if (h.isScheduledOn(d) && (d != open || h.isArchived)) {
        run = 0;
      }
    }
    d = d.addDays(1);
  }
  return HabitStreak(current: run, best: best);
}

/// One habit's done-out-of-planned over [from]..[to]. For a stay-clear habit,
/// days without a slip out of days the app saw.
Ratio habitRate(Ledger l, Habit h, DayKey from, DayKey to) {
  var done = 0;
  var planned = 0;
  // Days before the habit started, and (for a stay-clear habit) before the
  // app was first seen, count for nothing: start the walk after them.
  var start = from < h.createdDay ? h.createdDay : from;
  if (h.tracksSlips) {
    final seen = l._firstActiveDay;
    if (seen == null) return const Ratio(0, 0);
    if (start < seen) start = seen;
  }
  for (final d in start.through(to)) {
    if (!h.isActiveOn(d)) continue;
    final e = l.entryOf(h.id, d);
    if (e?.state == EntryState.skipped) continue;
    if (h.tracksSlips) {
      if (!l.wasSeen(d)) continue;
      planned++;
      if (e?.state != EntryState.slipped) done++;
      continue;
    }
    if (e?.state == EntryState.done) {
      planned++;
      done++;
    } else if (h.isScheduledOn(d) || e?.state == EntryState.partial) {
      planned++;
    }
  }
  return Ratio(done, planned);
}
