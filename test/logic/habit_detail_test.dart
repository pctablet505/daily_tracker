import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/logic/habit_detail.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';

Ledger ledger(
  List<Habit> habits, [
  List<Entry> entries = const [],
  List<DayKey> seen = const [],
]) => Ledger(habits: habits, entries: entries, seenDays: seen);

void main() {
  test('counts, streaks and the 30-day rate', () {
    final a = habit('a');
    final l = ledger(
      [a],
      [
        entry('a', thu),
        entry('a', fri),
        entry('a', sat),
        entry('a', sun, EntryState.skipped),
      ],
    );
    final d = buildHabitDetail(l, a, sun);
    expect(d.totalDone, 3);
    expect(d.streak, const HabitStreak(current: 3, best: 3));
    expect(d.rate30, const Ratio(3, 6)); // mon..sat planned, sun skipped
  });

  test('recent entries are newest first and limited', () {
    final a = habit('a');
    final l = ledger([a], [for (final d in mon.through(sun)) entry('a', d)]);
    final d = buildHabitDetail(l, a, sun, recentLimit: 3);
    expect(d.recent.map((e) => e.day), [sun, sat, fri]);
  });

  group('number habits', () {
    final w = habit('w', logType: LogType.number).copyWith(unit: () => 'kg');

    test(
      'give a series of values, oldest first, skipping entries without a value',
      () {
        final l = ledger(
          [w],
          [
            entry('w', mon, EntryState.done, 76),
            entry('w', wed, EntryState.done, 75.5),
            entry('w', fri, EntryState.skipped, 99),
          ],
        );
        final d = buildHabitDetail(l, w, sun);
        expect(d.series.map((p) => (p.day, p.value)), [
          (mon, 76.0),
          (wed, 75.5),
        ]);
        expect(d.latest, 75.5);
      },
    );

    test(
      'the change is latest minus the first value within the last 30 days',
      () {
        final l = ledger(
          [w],
          [
            entry(
              'w',
              const DayKey(2026, 8, 1),
              EntryState.done,
              90,
            ), // outside the window
            entry(
              'w',
              const DayKey(2026, 8, 27),
              EntryState.done,
              85,
            ), // 45 days back: still outside
            entry('w', const DayKey(2026, 9, 20), EntryState.done, 78),
            entry('w', sun, EntryState.done, 75.5),
          ],
        );
        final d = buildHabitDetail(l, w, sun);
        expect(d.change30, closeTo(-2.5, 1e-9));
      },
    );

    test('no change when there is only one value in the window', () {
      final l = ledger([w], [entry('w', sun, EntryState.done, 75.5)]);
      expect(buildHabitDetail(l, w, sun).change30, isNull);
    });

    test('a habit that is not a number habit has no series', () {
      final a = habit('a');
      expect(
        buildHabitDetail(
          ledger([a], [entry('a', mon, EntryState.done, 5)]),
          a,
          sun,
        ).series,
        isEmpty,
      );
    });
  });

  test('photo entries are listed newest first, excluding skipped days', () {
    final p = habit('p', logType: LogType.photo);
    Entry photo(DayKey d, String n, [EntryState s = EntryState.done]) => Entry(
      habitId: 'p',
      day: d,
      state: s,
      photoPath: n,
      loggedAt: DateTime.utc(2026),
    );
    final l = ledger(
      [p],
      [
        photo(mon, 'a.jpg'),
        photo(tue, 'skip.jpg', EntryState.skipped),
        photo(wed, 'b.jpg'),
        entry('p', fri),
      ],
    );
    expect(buildHabitDetail(l, p, sun).photos.map((e) => e.photoPath), [
      'b.jpg',
      'a.jpg',
    ]);
  });

  test('the last 12 weeks are shown as a grid of day states, oldest first', () {
    final a = habit('a', created: const DayKey(2026, 1, 1));
    final l = ledger(
      [a],
      [entry('a', sun), entry('a', sat, EntryState.skipped)],
    );
    final d = buildHabitDetail(l, a, sun);
    expect(d.recentDays.length, 84);
    expect(d.recentDays.last.day, sun);
    expect(d.recentDays.last.state, DotState.done);
    expect(d.recentDays[82].state, DotState.skipped);
    expect(d.recentDays[81].state, DotState.missed);
  });

  test('days before the habit existed or outside its schedule are not counted as missed', () {
    final a = habit('a', created: fri, mask: daysOf([5, 7]));
    final d = buildHabitDetail(ledger([a]), a, sun);
    final byDay = {for (final x in d.recentDays) x.day: x.state};
    expect(byDay[thu], DotState.none);
    expect(byDay[fri], DotState.missed);
    expect(byDay[sat], DotState.none);
    expect(byDay[sun], DotState.pending, reason: 'today is still open');
  });

  test('a stay-clear habit shows slips and clear days it was seen', () {
    final s = stayClear('s');
    final l = ledger([s], [slip('s', wed)], [mon, tue, thu]);
    final byDay = {
      for (final x in buildHabitDetail(l, s, sun).recentDays) x.day: x.state,
    };
    expect(byDay[mon], DotState.done);
    expect(byDay[wed], DotState.missed);
    expect(byDay[fri], DotState.none, reason: 'not opened, nothing known');
  });

  test(
    'a stay-clear habit started in year 1 counts its clear days quickly',
    () {
      final s = stayClear('s', created: const DayKey(1, 1, 1));
      final l = ledger([s], [slip('s', sat)], [fri, sat, sun]);
      final sw = Stopwatch()..start();
      final d = buildHabitDetail(l, s, sun);
      sw.stop();
      expect((d.totalDone, d.totalSlips), (2, 1));
      expect(sw.elapsedMilliseconds, lessThan(50));
    },
  );
}
