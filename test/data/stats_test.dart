import 'dart:isolate';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Ledger ledger(
  List<Habit> habits, [
  List<Entry> entries = const [],
  List<DayKey> seen = const [],
]) => Ledger(habits: habits, entries: entries, seenDays: seen);

/// Runs [count] in its own isolate, so a walk that never ends fails the test
/// instead of hanging it.
Future<Object?> endsInTime(Object? Function() count) async {
  final port = ReceivePort();
  final worker = await Isolate.spawn((job) => job.$2.send(job.$1()), (
    count,
    port.sendPort,
  ));
  try {
    return await port.first.timeout(const Duration(seconds: 20));
  } finally {
    worker.kill(priority: Isolate.immediate);
    port.close();
  }
}

void main() {
  group('summarizeDay: the 60% rule', () {
    // Five habits, [done] of them done on Monday.
    final five = [for (var i = 1; i <= 5; i++) habit('h$i')];
    for (final c in [
      (0, 60, DayStatus.missed),
      (2, 60, DayStatus.missed),
      (3, 60, DayStatus.good), // exactly 60% passes
      (4, 60, DayStatus.good),
      (5, 60, DayStatus.good),
      (4, 100, DayStatus.missed), // the threshold is a setting
      (5, 100, DayStatus.good),
      (1, 20, DayStatus.good),
    ]) {
      test('${c.$1} of 5 done at ${c.$2}% is ${c.$3.name}', () {
        final l = ledger(five, [
          for (var i = 1; i <= c.$1; i++) entry('h$i', mon),
        ]);
        final s = summarizeDay(l, mon, threshold: c.$2);
        expect(s.status, c.$3);
        expect((s.done, s.planned), (c.$1, 5));
      });
    }
  });

  group('summarizeDay: what is planned', () {
    test('a day with no habits is neutral', () {
      expect(summarizeDay(ledger([]), mon).status, DayStatus.neutral);
    });

    test('only the scheduled weekdays plan anything', () {
      final l = ledger([
        habit('a', mask: daysOf([1, 3, 5])),
      ]);
      expect(summarizeDay(l, mon).planned, 1);
      expect(summarizeDay(l, tue).planned, 0);
      expect(summarizeDay(l, tue).status, DayStatus.neutral);
      expect(summarizeDay(l, wed).planned, 1);
    });

    test(
      'nothing is planned before a habit exists; the end day is included',
      () {
        final l = ledger([habit('a', created: wed, end: fri)]);
        expect(summarizeDay(l, tue).planned, 0);
        expect(summarizeDay(l, wed).planned, 1);
        expect(summarizeDay(l, fri).planned, 1);
        expect(summarizeDay(l, sat).planned, 0);
      },
    );

    test('a habit done on a day it was not planned still counts as done', () {
      final l = ledger(
        [
          habit('a', mask: daysOf([1])),
        ],
        [entry('a', tue)],
      );
      final s = summarizeDay(l, tue);
      expect((s.done, s.planned, s.status), (1, 1, DayStatus.good));
    });

    test('a skipped day is left out of the count', () {
      final l = ledger(
        [habit('a'), habit('b')],
        [entry('a', mon), entry('b', mon, EntryState.skipped)],
      );
      final s = summarizeDay(l, mon);
      expect((s.done, s.planned, s.perfect), (1, 1, true));
    });

    test('a number habit short of its goal is planned but not done', () {
      final l = ledger(
        [habit('w', logType: LogType.number, goal: 8)],
        [entry('w', mon, EntryState.partial, 3)],
      );
      final s = summarizeDay(l, mon);
      expect((s.done, s.planned, s.status), (0, 1, DayStatus.missed));
    });

    test('a day taken off on a day the habit does not run plans nothing, even when it still holds an amount or a note', () {
      // Weekdays only; Saturday was logged as an extra and taken off again.
      final noted = entry(
        't',
        sat,
        EntryState.partial,
      ).copyWith(note: () => 'tired');
      for (final (h, kept) in [
        (
          habit('t', mask: Habit.weekdaysOnly),
          entry('t', sat, EntryState.partial, 5),
        ),
        (habit('t', mask: Habit.weekdaysOnly, logType: LogType.photo), noted),
        (habit('t', mask: Habit.weekdaysOnly, logType: LogType.number), noted),
      ]) {
        final l = ledger([h], [kept]);
        final s = summarizeDay(l, sat);
        expect((s.done, s.planned, s.status), (0, 0, DayStatus.neutral));
        expect(habitRate(l, h, sat, sat), const Ratio(0, 0));
        expect(rateOver(l, sat, sat), const Ratio(0, 0));
        expect(perfectDays(l, sat, sat), 0);
      }
    });

    test('an avoid habit in confirm mode is counted like any Do habit', () {
      final c = habit('c', kind: HabitKind.avoid, avoidMode: AvoidMode.confirm);
      expect(summarizeDay(ledger([c]), mon).planned, 1);
      expect(summarizeDay(ledger([c]), mon).status, DayStatus.missed);
      expect(
        summarizeDay(ledger([c], [entry('c', mon)]), mon).status,
        DayStatus.good,
      );
      expect(
        summarizeDay(ledger([c], [slip('c', mon)]), mon).status,
        DayStatus.missed,
      );
    });
  });

  group('summarizeDay: stay-clear habits', () {
    final s = stayClear('s');

    test('a seen day with no slip is good when nothing else is planned', () {
      expect(summarizeDay(ledger([s], [], [mon]), mon).status, DayStatus.good);
    });

    test('an unseen day with no slip is neutral, not a free pass', () {
      expect(summarizeDay(ledger([s]), mon).status, DayStatus.neutral);
    });

    test('a slip makes the day missed', () {
      final d = summarizeDay(ledger([s], [slip('s', mon)]), mon);
      expect((d.status, d.slips), (DayStatus.missed, 1));
    });

    test('a bonus entry of a Do habit makes the day a Do day', () {
      final l = ledger(
        [
          s,
          habit('a', mask: daysOf([2])),
        ],
        [entry('a', mon)],
      );
      expect(summarizeDay(l, mon).planned, 1);
    });

    test('an unseen day is known clear only for a stay-clear habit with its own entry, not through another habit', () {
      final t = stayClear('t');
      // Monday was never seen; another habit was logged then, and "I stayed
      // clear" answered for s alone.
      final other = ledger([s, t], [entry('other', mon)]);
      expect(summarizeDay(other, mon).status, DayStatus.neutral);
      expect(habitRate(other, s, mon, mon), const Ratio(0, 0));
      expect(habitStreak(other, s, mon).best, 0);
      final own = ledger([s, t], [entry('other', mon), entry('s', mon)]);
      expect(summarizeDay(own, mon).status, DayStatus.good);
      expect(habitRate(own, s, mon, mon), const Ratio(1, 1));
      expect(habitRate(own, t, mon, mon), const Ratio(0, 0));
      expect(habitStreak(own, s, mon).best, 1);
      expect(habitStreak(own, t, mon).best, 0);
    });

    test('counts the stay-clear habits not checked: no slip, no entry of their own, an unseen day', () {
      final l = ledger(
        [
          s,
          stayClear('kept'),
          stayClear('slipped'),
          stayClear('skipped'),
          stayClear('later', created: wed),
          habit('a'),
        ],
        [
          entry('kept', mon),
          slip('slipped', mon),
          entry('skipped', mon, EntryState.skipped),
        ],
      );
      expect(summarizeDay(l, mon).notChecked, 1);
      expect(summarizeDay(ledger([s], [], [mon]), mon).notChecked, 0);
    });

    test('before the habit existed it does not make a day good', () {
      expect(
        summarizeDay(
          ledger([stayClear('s', created: wed)], [], [mon]),
          mon,
        ).status,
        DayStatus.neutral,
      );
    });

    test('once Do habits are planned they decide the day, not the slips', () {
      final l = ledger([s, habit('a')], [slip('s', mon), entry('a', mon)]);
      final d = summarizeDay(l, mon);
      expect((d.status, d.slips), (DayStatus.good, 1));
    });
  });

  group('currentStreak', () {
    final a = habit('a');

    test('is 0 with no habits', () {
      expect(currentStreak(ledger([]), sun), 0);
    });

    test('counts good days back from today', () {
      final l = ledger(
        [a],
        [entry('a', fri), entry('a', sat), entry('a', sun)],
      );
      expect(currentStreak(l, sun), 3);
    });

    test('today still open does not break the run', () {
      final l = ledger([a], [entry('a', fri), entry('a', sat)]);
      expect(currentStreak(l, sun), 2);
    });

    test('a missed day before today ends the run', () {
      final l = ledger(
        [a],
        [entry('a', thu), entry('a', sat), entry('a', sun)],
      );
      expect(currentStreak(l, sun), 2); // fri missed
    });

    test('a missed yesterday and an open today is 0', () {
      final l = ledger([a], [entry('a', thu)]);
      expect(currentStreak(l, sat), 0); // fri missed, sat open
    });

    test('days with nothing planned are passed over', () {
      final weekdays = habit('w', mask: Habit.weekdaysOnly);
      final l = ledger(
        [weekdays],
        [
          entry('w', thu),
          entry('w', fri),
          entry('w', const DayKey(2026, 10, 12)),
        ],
      );
      expect(
        currentStreak(l, const DayKey(2026, 10, 12)),
        3,
      ); // Sat and Sun are neutral
    });

    test('does not reach back before anything existed', () {
      final l = ledger(
        [habit('n', created: sat)],
        [entry('n', sat), entry('n', sun)],
      );
      expect(currentStreak(l, sun), 2);
    });

    test('a skipped day neither counts nor breaks', () {
      final l = ledger(
        [a],
        [entry('a', fri), entry('a', sat, EntryState.skipped), entry('a', sun)],
      );
      expect(currentStreak(l, sun), 2);
    });

    test('stay-clear days count while the app is opened and end on a slip', () {
      final s = stayClear('s');
      final l = ledger([s], [slip('s', thu)], [fri, sat, sun]);
      expect(currentStreak(l, sun), 3);
      final slippedToday = ledger([s], [slip('s', sun)], [fri, sat, sun]);
      expect(currentStreak(slippedToday, sun), 0);
    });

    for (final early in [const DayKey(1970, 1, 1), const DayKey(1, 1, 1)]) {
      test('a seen day of $early, long before any habit, does not slow it', () {
        final l = ledger(
          [for (var i = 0; i < 20; i++) habit('h$i')],
          [
            for (var i = 0; i < 20; i++)
              for (final d in mon.through(sun)) entry('h$i', d),
          ],
          [early, ...mon.through(sun)],
        );
        final sw = Stopwatch()..start();
        final n = currentStreak(l, sun);
        sw.stop();
        expect(n, 7);
        expect(sw.elapsedMilliseconds, lessThan(50));
      });
    }
  });

  group('bestStreak', () {
    final a = habit('a');

    test('is the longest run, not the latest', () {
      final l = ledger(
        [a],
        [
          entry('a', mon),
          entry('a', tue),
          entry('a', wed),
          entry('a', fri),
          entry('a', sat),
        ],
      );
      expect(bestStreak(l, sun), 3);
    });

    test('an open today does not cut the final run', () {
      final l = ledger(
        [a],
        [entry('a', thu), entry('a', fri), entry('a', sat)],
      );
      expect(bestStreak(l, sun), 3);
    });

    test('is never below the current streak', () {
      final l = ledger(
        [a],
        [entry('a', fri), entry('a', sat), entry('a', sun)],
      );
      expect(bestStreak(l, sun), greaterThanOrEqualTo(currentStreak(l, sun)));
    });
  });

  group('rateOver', () {
    test(
      'adds planned and done across days instead of averaging day rates',
      () {
        // Monday 1 of 1, Tuesday 0 of 4: 1/5 summed, not the 50% a mean of day rates gives.
        final l = ledger(
          [
            habit('a'),
            habit('b', mask: daysOf([2])),
            habit('c', mask: daysOf([2])),
            habit('d', mask: daysOf([2])),
          ],
          [entry('a', mon)],
        );
        final r = rateOver(l, mon, mon.addDays(1));
        expect(
          r,
          const Ratio(1, 5),
        ); // Tuesday plans a, b, c, d; only Monday's a is done
        expect(r.fraction, closeTo(0.2, 1e-9));
      },
    );

    test('days before a habit existed add nothing', () {
      final l = ledger(
        [habit('a', created: fri)],
        [entry('a', fri), entry('a', sat), entry('a', sun)],
      );
      expect(rateOver(l, mon, sun), const Ratio(3, 3));
    });

    test('has no fraction when nothing was planned', () {
      expect(rateOver(ledger([]), mon, sun).fraction, isNull);
    });
  });

  group('perfectDays', () {
    test(
      'counts days with every planned Do habit done, and not empty days',
      () {
        final l = ledger(
          [habit('a'), habit('b')],
          [
            entry('a', mon),
            entry('b', mon),
            entry('a', tue),
            entry('a', wed),
            entry('b', wed),
          ],
        );
        expect(perfectDays(l, mon, sun), 2); // Mon and Wed
      },
    );

    test(
      'with only stay-clear habits, a seen day without a slip is perfect',
      () {
        final l = ledger([stayClear('s')], [slip('s', tue)], [mon, tue, wed]);
        expect(summarizeDay(l, mon).perfect, isTrue);
        expect(summarizeDay(l, tue).perfect, isFalse); // slipped
        expect(summarizeDay(l, thu).perfect, isFalse); // not seen: neutral
        expect(perfectDays(l, mon, sun), 2); // Mon and Wed
      },
    );
  });

  group('habitStreak: a Do habit', () {
    test('counts planned days done; an open today does not break it', () {
      final a = habit('a');
      final l = ledger(
        [a],
        [
          entry('a', mon), entry('a', tue), entry('a', wed), // 3
          entry('a', fri), entry('a', sat), // thu missed -> 2
        ],
      );
      expect(habitStreak(l, a, sun), const HabitStreak(current: 2, best: 3));
    });

    test('days it is not planned for do not break it', () {
      final a = habit('a', mask: daysOf([1, 3, 5]));
      final l = ledger(
        [a],
        [entry('a', mon), entry('a', wed), entry('a', fri)],
      );
      expect(habitStreak(l, a, sun), const HabitStreak(current: 3, best: 3));
    });

    test('a skipped day is passed over', () {
      final a = habit('a');
      final l = ledger(
        [a],
        [entry('a', mon), entry('a', tue, EntryState.skipped), entry('a', wed)],
      );
      expect(habitStreak(l, a, wed), const HabitStreak(current: 2, best: 2));
    });

    test('an archived habit stops at its last day', () {
      final a = habit('a', end: wed);
      final l = ledger(
        [a],
        [entry('a', mon), entry('a', tue), entry('a', wed)],
      );
      expect(habitStreak(l, a, sun), const HabitStreak(current: 3, best: 3));
    });

    test('an archived habit missed on its last day has no streak, on that day or after', () {
      final a = habit('a', end: wed);
      final l = ledger([a], [entry('a', mon), entry('a', tue)]);
      expect(habitStreak(l, a, wed), const HabitStreak(current: 0, best: 2));
      expect(habitStreak(l, a, thu), const HabitStreak(current: 0, best: 2));
    });

    test('a missed day today is not yet a miss', () {
      final a = habit('a');
      final l = ledger([a], [entry('a', mon)]);
      expect(habitStreak(l, a, tue), const HabitStreak(current: 1, best: 1));
      expect(habitStreak(l, a, wed), const HabitStreak(current: 0, best: 1));
    });

    test('a past day looked back on is not open: missing it was a miss', () {
      final a = habit('a');
      final l = ledger(
        [a],
        [entry('a', mon), entry('a', tue), entry('a', wed)],
      );
      expect(
        habitStreak(l, a, thu, today: fri),
        const HabitStreak(current: 0, best: 3),
      );
      expect(
        habitStreak(l, a, fri, today: fri),
        const HabitStreak(current: 0, best: 3),
      );
      expect(
        habitStreak(l, a, thu, today: thu),
        const HabitStreak(current: 3, best: 3),
      );
    });
  });

  group('habitStreak: a stay-clear habit', () {
    final s = stayClear('s');

    test('is the seen days since the last slip', () {
      final l = ledger([s], [slip('s', thu)], [mon, tue, wed, fri, sat, sun]);
      expect(habitStreak(l, s, sun), const HabitStreak(current: 3, best: 3));
    });

    test('days the app was not opened are not counted', () {
      final l = ledger([s], [slip('s', wed)], [mon, tue, fri]);
      expect(habitStreak(l, s, sun), const HabitStreak(current: 1, best: 2));
    });

    test('a slip today starts again at 0', () {
      final l = ledger([s], [slip('s', sun)], [
        mon,
        tue,
        wed,
        thu,
        fri,
        sat,
        sun,
      ]);
      expect(habitStreak(l, s, sun), const HabitStreak(current: 0, best: 6));
    });
  });

  group('habitRate', () {
    test('Do habit: done over planned, skipped days left out', () {
      final a = habit('a');
      final l = ledger(
        [a],
        [entry('a', mon), entry('a', tue), entry('a', wed, EntryState.skipped)],
      );
      expect(
        habitRate(l, a, mon, fri),
        const Ratio(2, 4),
      ); // mon, tue done; thu, fri missed
    });

    test('stay-clear habit: slip-free seen days over seen days', () {
      final s = stayClear('s');
      final l = ledger([s], [slip('s', tue)], [mon, tue, wed]);
      expect(habitRate(l, s, mon, sun), const Ratio(2, 3));
    });
  });

  group('Ledger.entriesOf', () {
    test('lists one habit\'s entries, oldest first, and nothing for an unknown habit', () {
      final l = ledger(
        [habit('a'), habit('b')],
        [entry('a', wed), entry('b', tue), entry('a', mon)],
      );
      expect(l.entriesOf('a').map((e) => e.day), [mon, wed]);
      expect(l.entriesOf('zzz'), isEmpty);
    });
  });

  group('every walk ends at the ends of the calendar', () {
    test('a ledger that begins on 0001-01-01', () async {
      const start = DayKey(1, 1, 1);
      final s = stayClear('s', created: start);
      final a = habit('a', created: start, end: start);
      final l = ledger([s, a], [entry('a', start)], [start, sun]);
      expect(await endsInTime(() => currentStreak(l, sun)), 2);
      expect(await endsInTime(() => bestStreak(l, sun)), 2);
      expect(
        await endsInTime(() => habitStreak(l, a, sun)),
        const HabitStreak(current: 1, best: 1),
      );
      expect(
        await endsInTime(() => habitStreak(l, s, sun)),
        const HabitStreak(current: 2, best: 2),
      );
      expect(
        await endsInTime(() => habitRate(l, a, start, sun)),
        const Ratio(1, 1),
      );
      expect(
        await endsInTime(() => habitRate(l, s, start, sun)),
        const Ratio(2, 2),
      );
      expect(
        await endsInTime(() => rateOver(l, start, sun)),
        const Ratio(1, 1),
      );
      expect(await endsInTime(() => perfectDays(l, start, sun)), 2);
    });

    test('a ledger that reaches 9999-12-31', () async {
      const last = DayKey(9999, 12, 31);
      final before = last.addDays(-1);
      final s = stayClear('s', created: before);
      final a = habit('a', created: before);
      final l = ledger([s, a], [entry('a', before), entry('a', last)], [
        before,
        last,
      ]);
      expect(await endsInTime(() => currentStreak(l, last)), 2);
      expect(await endsInTime(() => bestStreak(l, last)), 2);
      expect(
        await endsInTime(() => habitStreak(l, a, last)),
        const HabitStreak(current: 2, best: 2),
      );
      expect(
        await endsInTime(() => habitStreak(l, s, last)),
        const HabitStreak(current: 2, best: 2),
      );
      expect(
        await endsInTime(() => habitRate(l, a, before, last)),
        const Ratio(2, 2),
      );
      expect(
        await endsInTime(() => rateOver(l, before, last)),
        const Ratio(2, 2),
      );
      expect(await endsInTime(() => perfectDays(l, before, last)), 2);
    });
  });
}
