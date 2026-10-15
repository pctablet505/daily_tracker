import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/logic/progress_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';

Ledger ledger(
  List<Habit> habits, [
  List<Entry> entries = const [],
  List<DayKey> seen = const [],
]) => Ledger(habits: habits, entries: entries, seenDays: seen);

void main() {
  group('heat level of a day', () {
    DaySummary day(
      int planned,
      int done, {
      int slips = 0,
      DayStatus status = DayStatus.good,
    }) => DaySummary(
      day: mon,
      planned: planned,
      done: done,
      slips: slips,
      status: status,
    );

    for (final c in <(int, int, HeatLevel)>[
      (4, 0, HeatLevel.missed),
      (4, 1, HeatLevel.low),
      (4, 2, HeatLevel.mid),
      (4, 3, HeatLevel.mid),
      (4, 4, HeatLevel.full),
      (1, 1, HeatLevel.full),
      (3, 1, HeatLevel.low),
    ]) {
      test(
        '${c.$2} of ${c.$1} is ${c.$3.name}',
        () => expect(heatLevel(day(c.$1, c.$2), isFuture: false), c.$3),
      );
    }

    test('nothing planned: a clear day is full, a slip is missed, an unknown day is none', () {
      expect(
        heatLevel(day(0, 0, status: DayStatus.good), isFuture: false),
        HeatLevel.full,
      );
      expect(
        heatLevel(
          day(0, 0, slips: 1, status: DayStatus.missed),
          isFuture: false,
        ),
        HeatLevel.missed,
      );
      expect(
        heatLevel(day(0, 0, status: DayStatus.neutral), isFuture: false),
        HeatLevel.none,
      );
    });

    test('99 of 100 is still not full', () {
      expect(heatLevel(day(100, 99), isFuture: false), HeatLevel.mid);
    });

    test('a future day is future whatever it holds', () {
      expect(heatLevel(day(4, 4), isFuture: true), HeatLevel.future);
    });

    test('today with nothing done and no slip is none, not missed', () {
      HeatLevel today(DaySummary s) =>
          heatLevel(s, isFuture: false, isToday: true);
      expect(today(day(4, 0, status: DayStatus.missed)), HeatLevel.none);
      expect(
        today(day(4, 0, slips: 1, status: DayStatus.missed)),
        HeatLevel.missed,
      );
      expect(today(day(4, 1, status: DayStatus.missed)), HeatLevel.low);
      expect(today(day(0, 0)), HeatLevel.full, reason: 'stay-clear, held');
    });
  });

  group('month grid', () {
    test('starts under the right weekday and covers every day', () {
      // October 2026 begins on a Thursday: three blanks (Mon, Tue, Wed).
      final cells = monthGrid(ledger([habit('a')]), 2026, 10, today: sun);
      expect(cells.take(3).every((c) => c.day == null), isTrue);
      expect(cells[3].day, const DayKey(2026, 10, 1));
      expect(cells.where((c) => c.day != null).length, 31);
      expect(cells.last.day, const DayKey(2026, 10, 31));
    });

    test(
      'a month starting on Monday has no blanks; February 2027 has 28 days',
      () {
        expect(
          monthGrid(ledger([]), 2026, 6, today: sun).first.day,
          const DayKey(2026, 6, 1),
        ); // 1 June 2026 is a Monday
        expect(
          monthGrid(
            ledger([]),
            2027,
            2,
            today: sun,
          ).where((c) => c.day != null).length,
          28,
        );
        expect(
          monthGrid(
            ledger([]),
            2028,
            2,
            today: sun,
          ).where((c) => c.day != null).length,
          29,
        );
      },
    );

    test('December ends the year correctly', () {
      final cells = monthGrid(ledger([]), 2026, 12, today: sun);
      expect(cells.where((c) => c.day != null).length, 31);
      expect(cells.last.day, const DayKey(2026, 12, 31));
    });

    test('days after today are future, today and earlier are not', () {
      final cells = monthGrid(
        ledger([habit('a')], [entry('a', mon)]),
        2026,
        10,
        today: sun,
      );
      DayHeat at(int d) => cells.firstWhere((c) => c.day?.day == d);
      expect(at(5).level, HeatLevel.full);
      expect(at(6).level, HeatLevel.missed);
      expect(at(11).level, HeatLevel.none, reason: 'today, nothing done yet');
      expect(at(12).level, HeatLevel.future);
    });

    test('today is drawn as missed only once something on it went wrong', () {
      final hs = [habit('a'), habit('b'), stayClear('s')];
      DayHeat today(List<Entry> entries) => monthGrid(
        ledger(hs, entries, [sun]),
        2026,
        10,
        today: sun,
      ).firstWhere((c) => c.day == sun);
      expect(today([]).level, HeatLevel.none);
      expect(today([entry('a', sun)]).level, HeatLevel.mid);
      expect(today([slip('s', sun)]).level, HeatLevel.missed);
      expect(
        monthGrid(
          ledger(hs),
          2026,
          10,
          today: mon,
        ).firstWhere((c) => c.day == sun).level,
        HeatLevel.future,
      );
    });

    test('days before anything existed are none', () {
      final cells = monthGrid(
        ledger([habit('a', created: wed)]),
        2026,
        10,
        today: sun,
      );
      expect(cells.firstWhere((c) => c.day?.day == 2).level, HeatLevel.none);
    });
  });

  group('needs attention', () {
    test(
      'lists the weakest habits first, and only those planned enough times',
      () {
        final a = habit('a'); // done 1 of 7
        final b = habit('b'); // done 6 of 7
        final c = habit('c'); // done 0 of 7
        final d = habit('d', created: sat); // planned only 2 times
        final l = ledger(
          [a, b, c, d],
          [
            entry('a', mon),
            for (final x in [mon, tue, wed, thu, fri, sat]) entry('b', x),
          ],
        );
        final items = needsAttention(l, mon, sun, limit: 3);
        expect(items.map((i) => i.habit.id), ['c', 'a', 'b']);
        expect(items.first.ratio, const Ratio(0, 7));
      },
    );

    test('a habit with a perfect record is not listed', () {
      final l = ledger(
        [habit('a')],
        [for (final x in mon.through(sun)) entry('a', x)],
      );
      expect(needsAttention(l, mon, sun), isEmpty);
    });

    test(
      'respects the limit and leaves out stay-clear and archived habits',
      () {
        final l = ledger([
          habit('a'),
          habit('b'),
          habit('c'),
          habit('d'),
          habit(
            'archived',
            created: const DayKey(2026, 9, 1),
            end: const DayKey(2026, 10, 4),
          ),
          stayClear('s'),
        ]);
        expect(needsAttention(l, mon, sun, limit: 2).length, 2);
        final all = needsAttention(
          l,
          mon,
          sun,
          limit: 9,
        ).map((i) => i.habit.id);
        expect(all, isNot(contains('s')));
        expect(all, isNot(contains('archived')));
      },
    );

    test(
      'a habit archived since is still judged on the month it was active',
      () {
        const sep1 = DayKey(2026, 9, 1);
        const sep30 = DayKey(2026, 9, 30);
        final a = habit('a', created: sep1, end: const DayKey(2026, 10, 4));
        final l = ledger([a], [entry('a', sep1)]);
        expect(
          needsAttention(l, sep1, sep30).map((i) => (i.habit.id, i.ratio)),
          [('a', const Ratio(1, 30))],
        );
      },
    );

    test('today, still open and not done, is not held against a habit', () {
      final a = habit('a'); // done Mon and Tue; Wednesday is today
      final l = ledger([a], [entry('a', mon), entry('a', tue)]);
      expect(needsAttention(l, mon, wed, today: wed), isEmpty);
      final b = habit('b'); // done Mon and Wed, missed Tue; Thursday is today
      final m = ledger([b], [entry('b', mon), entry('b', wed)]);
      expect(
        needsAttention(m, mon, thu, today: thu).single.ratio,
        const Ratio(2, 3),
      );
      final done = ledger([b], [entry('b', mon), entry('b', thu)]);
      expect(
        needsAttention(done, mon, thu, today: thu).single.ratio,
        const Ratio(2, 4),
        reason: 'today counts once it is done',
      );
      expect(
        needsAttention(m, mon, thu).single.ratio,
        const Ratio(2, 4),
        reason: 'without a today every day counts, as before',
      );
    });

    test('a stay-clear habit with slips is not listed here', () {
      final s = stayClear('s');
      final l = ledger([s], [slip('s', mon), slip('s', tue), slip('s', wed)]);
      expect(needsAttention(l, mon, sun), isEmpty);
    });

    test('ties are broken by list order', () {
      final l = ledger([
        habit('x').copyWith(sortOrder: 2),
        habit('y').copyWith(sortOrder: 1),
      ]);
      expect(needsAttention(l, mon, sun).map((i) => i.habit.id), ['y', 'x']);
    });
  });

  group('by area', () {
    test('groups habits by area, best first, with "Other" for none', () {
      final l = ledger(
        [
          habit('a', area: 'Health'),
          habit('b', area: 'Health'),
          habit('c', area: 'Mind'),
          habit('d'),
        ],
        [entry('a', mon), entry('b', mon), entry('c', mon), entry('c', tue)],
      );
      final r = areaRates(l, mon, tue);
      expect(
        {for (final x in r) x.area: x.ratio},
        {
          'Health': const Ratio(2, 4),
          'Mind': const Ratio(2, 2),
          'Other': const Ratio(0, 2),
        },
      );
      expect(r.map((x) => x.area), ['Mind', 'Health', 'Other']);
    });

    test('breaks ties alphabetically by area name', () {
      final l = ledger([habit('a', area: 'Work'), habit('b', area: 'Body')]);
      expect(areaRates(l, mon, tue).map((x) => x.area), ['Body', 'Work']);
    });

    test('leaves out areas with nothing planned and stay-clear habits', () {
      final l = ledger([
        habit('a', area: 'Health', created: sun),
        stayClear('s').copyWith(area: () => 'Mind'),
      ]);
      expect(areaRates(l, mon, sat), isEmpty);
    });
  });

  test('lastDays gives n days ending today, oldest first', () {
    final l = ledger([habit('a')], [entry('a', sat), entry('a', sun)]);
    final days = lastDays(l, sun, 7);
    expect(days.map((d) => d.day), [mon, tue, wed, thu, fri, sat, sun]);
    expect(days.last.done, 1);
  });

  test('the 30-day rate covers exactly 30 days ending today', () {
    final l = ledger([habit('a', created: const DayKey(2026, 8, 1))]);
    expect(progressStats(l, sun).rate30, const Ratio(0, 30));
  });

  test('stats for the progress screen', () {
    final a = habit('a');
    final l = ledger(
      [a],
      [entry('a', thu), entry('a', fri), entry('a', sat), entry('a', sun)],
    );
    final s = progressStats(l, sun, threshold: 60);
    expect(s.currentStreak, 4);
    expect(s.bestStreak, 4);
    expect(s.perfectDays, 4);
    expect(
      s.rate30,
      const Ratio(4, 7),
    ); // the habit started Monday; 7 days planned, 4 done
  });
}
