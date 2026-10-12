import '../core/day_key.dart';
import '../data/models.dart';
import '../data/stats.dart';

/// How a day is drawn on the calendar heat map.
enum HeatLevel { none, missed, low, mid, full, future }

HeatLevel heatLevel(DaySummary s, {required bool isFuture}) {
  if (isFuture) return HeatLevel.future;
  if (s.planned == 0) {
    return switch (s.status) {
      DayStatus.good => HeatLevel.full,
      DayStatus.missed => HeatLevel.missed,
      DayStatus.neutral => HeatLevel.none,
    };
  }
  final f = s.done / s.planned;
  if (f == 0) return HeatLevel.missed;
  if (f < 0.5) return HeatLevel.low;
  if (f < 1) return HeatLevel.mid;
  return HeatLevel.full;
}

/// One calendar cell. [day] is null for the blanks before the 1st.
final class DayHeat {
  const DayHeat({required this.day, required this.level, this.summary});
  final DayKey? day;
  final HeatLevel level;
  final DaySummary? summary;
}

/// The cells of a Monday-first month grid: blanks, then every day of the month.
List<DayHeat> monthGrid(
  Ledger l,
  int year,
  int month, {
  required DayKey today,
  int threshold = defaultStreakThreshold,
}) {
  final first = DayKey(year, month, 1);
  final next = month == 12
      ? DayKey(year + 1, 1, 1)
      : DayKey(year, month + 1, 1);
  final cells = <DayHeat>[
    for (var i = 0; i < first.weekday - 1; i++)
      const DayHeat(day: null, level: HeatLevel.none),
  ];
  for (final d in first.through(next.addDays(-1))) {
    final s = summarizeDay(l, d, threshold: threshold);
    cells.add(
      DayHeat(
        day: d,
        level: heatLevel(s, isFuture: d > today),
        summary: s,
      ),
    );
  }
  return cells;
}

final class AttentionItem {
  const AttentionItem(this.habit, this.ratio);
  final Habit habit;
  final Ratio ratio;
}

/// The Do habits with the lowest done-rate over [from]..[to]. Habits planned
/// fewer than [minPlanned] times are left out (too little to judge), as are
/// those with a perfect record.
List<AttentionItem> needsAttention(
  Ledger l,
  DayKey from,
  DayKey to, {
  int limit = 3,
  int minPlanned = 3,
}) {
  final items =
      <AttentionItem>[
            for (final h in l.habits)
              if (!h.tracksSlips && !h.isArchived)
                AttentionItem(h, habitRate(l, h, from, to)),
          ]
          .where(
            (i) =>
                i.ratio.planned >= minPlanned && i.ratio.done < i.ratio.planned,
          )
          .toList();
  items.sort((a, b) {
    final c = a.ratio.fraction!.compareTo(b.ratio.fraction!);
    return c != 0 ? c : a.habit.sortOrder.compareTo(b.habit.sortOrder);
  });
  return items.take(limit).toList();
}

final class AreaRate {
  const AreaRate(this.area, this.ratio);
  final String area;
  final Ratio ratio;
}

/// Done-out-of-planned per area over [from]..[to], best first. Habits with no area are "Other".
List<AreaRate> areaRates(Ledger l, DayKey from, DayKey to) {
  final done = <String, int>{};
  final planned = <String, int>{};
  for (final h in l.habits) {
    if (h.tracksSlips) continue;
    final r = habitRate(l, h, from, to);
    final key = h.area ?? 'Other';
    done[key] = (done[key] ?? 0) + r.done;
    planned[key] = (planned[key] ?? 0) + r.planned;
  }
  final out = [
    for (final k in planned.keys)
      if (planned[k]! > 0) AreaRate(k, Ratio(done[k]!, planned[k]!)),
  ];
  out.sort((a, b) {
    final c = b.ratio.fraction!.compareTo(a.ratio.fraction!);
    return c != 0 ? c : a.area.compareTo(b.area);
  });
  return out;
}

/// The [n] days ending [today], oldest first.
List<DaySummary> lastDays(
  Ledger l,
  DayKey today,
  int n, {
  int threshold = defaultStreakThreshold,
}) => [
  for (final d in today.addDays(-(n - 1)).through(today))
    summarizeDay(l, d, threshold: threshold),
];

final class ProgressStats {
  const ProgressStats({
    required this.currentStreak,
    required this.bestStreak,
    required this.rate30,
    required this.perfectDays,
  });
  final int currentStreak;
  final int bestStreak;

  /// Done out of planned over the last 30 days.
  final Ratio rate30;

  /// Days in the last 30 on which every planned habit was done.
  final int perfectDays;
}

ProgressStats progressStats(
  Ledger l,
  DayKey today, {
  int threshold = defaultStreakThreshold,
}) {
  final from = today.addDays(-29);
  return ProgressStats(
    currentStreak: currentStreak(l, today, threshold: threshold),
    bestStreak: bestStreak(l, today, threshold: threshold),
    rate30: rateOver(l, from, today, threshold: threshold),
    perfectDays: perfectDays(l, from, today),
  );
}
