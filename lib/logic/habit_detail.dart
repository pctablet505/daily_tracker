import '../core/day_key.dart';
import '../data/models.dart';
import '../data/stats.dart';

/// How one day looks in a habit's own 12-week grid.
enum DotState { none, done, missed, skipped, pending }

final class HabitDayDot {
  const HabitDayDot(this.day, this.state);
  final DayKey day;
  final DotState state;
}

final class ValuePoint {
  const ValuePoint(this.day, this.value);
  final DayKey day;
  final double value;
}

/// Everything the habit page shows.
final class HabitDetail {
  const HabitDetail({
    required this.streak,
    required this.rate30,
    required this.totalDone,
    required this.recent,
    required this.series,
    required this.latest,
    required this.change30,
    required this.photos,
    required this.recentDays,
  });

  final HabitStreak streak;
  final Ratio rate30;
  final int totalDone;

  /// Newest first.
  final List<Entry> recent;

  /// Number habits: values oldest first.
  final List<ValuePoint> series;
  final double? latest;

  /// Latest minus the first value of the last 30 days, or null with fewer than two values there.
  final double? change30;

  /// Entries with a photo, newest first.
  final List<Entry> photos;

  /// The 84 days (12 weeks) ending today, oldest first.
  final List<HabitDayDot> recentDays;
}

HabitDetail buildHabitDetail(
  Ledger l,
  Habit h,
  DayKey today, {
  int recentLimit = 20,
}) {
  final all = l.entriesOf(h.id);
  final newestFirst = all.reversed.toList();
  final series = h.logType == LogType.number
      ? [
          for (final e in all)
            if (e.value != null && e.state != EntryState.skipped)
              ValuePoint(e.day, e.value!),
        ]
      : <ValuePoint>[];
  final windowStart = today.addDays(-29);
  final inWindow = series
      .where((p) => p.day >= windowStart && p.day <= today)
      .toList();
  final change = inWindow.length >= 2
      ? inWindow.last.value - inWindow.first.value
      : null;

  final dots = <HabitDayDot>[];
  for (final d in today.addDays(-83).through(today)) {
    final e = l.entryOf(h.id, d);
    final DotState s;
    if (e?.state == EntryState.skipped) {
      s = DotState.skipped;
    } else if (h.tracksSlips) {
      if (e?.state == EntryState.slipped) {
        s = DotState.missed;
      } else if (h.isActiveOn(d) && l.wasSeen(d)) {
        s = DotState.done;
      } else {
        s = DotState.none;
      }
    } else if (e?.state == EntryState.done) {
      s = DotState.done;
    } else if (h.isScheduledOn(d)) {
      s = d == today ? DotState.pending : DotState.missed;
    } else {
      s = DotState.none;
    }
    dots.add(HabitDayDot(d, s));
  }

  return HabitDetail(
    streak: habitStreak(l, h, today),
    rate30: habitRate(l, h, windowStart, today),
    totalDone: all.where((e) => e.state == EntryState.done).length,
    recent: newestFirst.take(recentLimit).toList(),
    series: series,
    latest: series.isEmpty ? null : series.last.value,
    change30: change,
    photos: [
      for (final e in newestFirst)
        if (e.photoPath != null && e.state != EntryState.skipped) e,
    ],
    recentDays: dots,
  );
}
