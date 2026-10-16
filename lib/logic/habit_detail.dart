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
    this.totalSlips = 0,
    required this.recent,
    required this.series,
    required this.latest,
    required this.change30,
    required this.photos,
    required this.photoCount,
    required this.recentDays,
  });

  final HabitStreak streak;
  final Ratio rate30;
  final int totalDone;
  final int totalSlips;

  /// Newest first.
  final List<Entry> recent;

  /// Number habits: values oldest first.
  final List<ValuePoint> series;
  final double? latest;

  /// Latest minus the first value of the last 30 days, or null with fewer than two values there.
  final double? change30;

  /// Entries with a photo, newest first.
  final List<Entry> photos;

  /// Photos whose file is on this phone: a restore on a new phone brings
  /// back the entries but not the files, and those are not counted.
  final int photoCount;

  /// The 84 days (12 weeks) ending today, oldest first.
  final List<HabitDayDot> recentDays;
}

HabitDetail buildHabitDetail(
  Ledger l,
  Habit stored,
  DayKey today, {
  int recentLimit = 20,
  bool Function(String photoName)? photoExists,
}) {
  // A habit archived on the day it started stores an end the day before it;
  // its first day still belongs to it, for every count on the page.
  final end = stored.endDay;
  final h = end != null && end < stored.createdDay
      ? stored.copyWith(endDay: () => stored.createdDay)
      : stored;
  final anchor = (h.endDay != null && h.endDay! < today) ? h.endDay! : today;
  final all = [
    for (final e in l.entriesOf(h.id))
      if (e.day <= anchor) e,
  ];
  final newestFirst = all.reversed.toList();
  final series = h.logType == LogType.number
      ? [
          for (final e in all)
            if (e.value != null && e.state != EntryState.skipped)
              ValuePoint(e.day, e.value!),
        ]
      : <ValuePoint>[];
  final windowStart = anchor.addDays(-29);
  final inWindow = series
      .where((p) => p.day >= windowStart && p.day <= anchor)
      .toList();
  final change = inWindow.length >= 2
      ? inWindow.last.value - inWindow.first.value
      : null;

  final dots = <HabitDayDot>[];
  for (final d in anchor.addDays(-83).through(anchor)) {
    final e = l.entryOf(h.id, d);
    final DotState s;
    if (!h.isActiveOn(d)) {
      s = DotState.none;
    } else if (e?.state == EntryState.skipped) {
      s = DotState.skipped;
    } else if (h.tracksSlips) {
      if (e?.state == EntryState.slipped) {
        s = DotState.missed;
      } else if (l.wasSeen(h.id, d)) {
        s = DotState.done;
      } else {
        s = DotState.none;
      }
    } else if (e?.state == EntryState.done) {
      s = DotState.done;
    } else if (plannedNotDone(h, d, e)) {
      s = d == today && !h.isArchived ? DotState.pending : DotState.missed;
    } else {
      s = DotState.none;
    }
    dots.add(HabitDayDot(d, s));
  }

  final totalDone = h.tracksSlips
      ? habitRate(l, h, h.createdDay, anchor).done
      : all.where((e) => e.state == EntryState.done).length;
  final totalSlips = all.where((e) => e.state == EntryState.slipped).length;
  final photos = [
    for (final e in newestFirst)
      if (e.photoPath != null && e.state != EntryState.skipped) e,
  ];

  return HabitDetail(
    streak: habitStreak(l, h, today),
    rate30: habitRate(l, h, windowStart, anchor),
    totalDone: totalDone,
    totalSlips: totalSlips,
    recent: newestFirst.take(recentLimit).toList(),
    series: series,
    latest: series.isEmpty ? null : series.last.value,
    change30: change,
    photos: photos,
    photoCount: photos
        .where((e) => photoExists?.call(e.photoPath!) ?? true)
        .length,
    recentDays: dots,
  );
}
