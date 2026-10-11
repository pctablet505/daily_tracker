// Regression tests for defects found in review. Each test states the behaviour the app
// promises; a red result is a finding.
import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/logic/progress_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';

void main() {
  // Two full weeks before the fixture week: Mon 2026-09-21 .. Sun 2026-10-11.
  const start = DayKey(2026, 9, 21);
  const today = sun; // 2026-10-11, a Sunday

  test('a slip stops a day being perfect, but does not undo enough done', () {
    final l = Ledger(
      habits: [habit('do'), stayClear('s')],
      entries: [entry('do', wed), slip('s', wed)],
      seenDays: [wed],
    );
    final s = summarizeDay(l, wed);
    expect(s.status, DayStatus.good);
    expect(s.perfect, isFalse);
    expect(perfectDays(l, wed, wed), 0);
    final clean = Ledger(
      habits: [habit('do'), stayClear('s')],
      entries: [entry('do', wed)],
      seenDays: [wed],
    );
    expect(summarizeDay(clean, wed).perfect, isTrue);
    expect(perfectDays(clean, wed, wed), 1);
  });

  test('a day with nothing but stay-clear habits is missed by a slip', () {
    final l = Ledger(
      habits: [stayClear('s')],
      entries: [slip('s', wed)],
      seenDays: [wed],
    );
    expect(summarizeDay(l, wed).status, DayStatus.missed);
  });

  test('days with nothing planned do not cut a best streak short', () {
    // Weekdays only, done every weekday for two weeks: the weekends in between are neutral.
    final h = habit('a', created: mon, mask: Habit.weekdaysOnly);
    final entries = [
      for (final d in mon.through(mon.addDays(11)))
        if (d.weekday <= 5) entry('a', d),
    ];
    final l = Ledger(habits: [h], entries: entries);
    expect(bestStreak(l, mon.addDays(11)), 10);
  });

  test('perfect days count only days where everything planned was done', () {
    final l = Ledger(
      habits: [habit('a'), habit('b'), habit('c')],
      entries: [
        entry('a', mon), entry('b', mon), entry('c', mon), // perfect
        entry('a', tue), entry('b', tue), // 2 of 3: good at 60%, not perfect
      ],
    );
    expect(summarizeDay(l, tue).status, DayStatus.good);
    expect(perfectDays(l, mon, tue), 1);
  });

  test(
    'a backup habit created on 0001-01-01 does not stall the progress screen',
    () {
      final old = habit('a', created: const DayKey(1, 1, 1));
      final habits = [
        old,
        for (var i = 0; i < 9; i++) habit('h$i', created: start),
      ];
      final l = Ledger(habits: habits, entries: [entry('a', today)]);
      final sw = Stopwatch()..start();
      progressStats(l, today);
      sw.stop();
      // ignore: avoid_print
      print('progressStats with a year-1 habit: ${sw.elapsedMilliseconds} ms');
      expect(sw.elapsedMilliseconds, lessThan(250));
    },
  );
}
